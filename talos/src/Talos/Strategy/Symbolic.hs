{-# Language OverloadedStrings #-}
{-# Language GeneralizedNewtypeDeriving #-}

-- FIXME: much of this file is similar to Synthesis, maybe factor out commonalities
module Talos.Strategy.Symbolic (symbolicStrat) where

import Control.Monad.Reader

import           Control.Monad.State
import qualified Data.ByteString              as BS
import           Data.List                    (foldl', foldl1', partition)
import qualified Data.Map                     as Map
import qualified Data.Set                     as Set

import           Data.Word                    (Word8)

import           Daedalus.PP                  hiding (empty)
import           Daedalus.Panic

import           Daedalus.Core                hiding (streamOffset)
import           Daedalus.Core.Free           (freeVars)
import qualified Daedalus.Core.Semantics.Env  as I
import qualified Daedalus.Core.Semantics.Expr as I
import           Daedalus.Core.Type
import qualified Daedalus.Value               as I

import qualified SimpleSMT                    as S

import           Talos.Analysis.EntangledVars
import           Talos.Analysis.Projection    (projectE, typeToInhabitant)
import           Talos.Analysis.Slice
import           Talos.Strategy.Monad
import           Talos.Strategy.SymbolicM

import           Talos.SymExec.Expr           (symExecCaseAlts) -- for GCase
import           Talos.SymExec.Funs           (defineSliceFunDefs,
                                               defineSlicePolyFuns)
import           Talos.SymExec.ModelParser    (evalModelP, pByte, pValue)
import           Talos.SymExec.Path
import           Talos.SymExec.SemiExpr
import           Talos.SymExec.SemiValue      as SE
import           Talos.SymExec.SolverT        (SolverT, declareName,
                                               declareSymbol, reset,
                                               scoped)
import qualified Talos.SymExec.SolverT        as Solv hiding (getName)
import           Talos.SymExec.StdLib
import           Talos.SymExec.Type           (defineSliceTypeDefs, symExecTy)

-- ----------------------------------------------------------------------------------------
-- Backtracking random strats

symbolicStrat :: Strategy
symbolicStrat =
  Strategy { stratName  = "symbolic"
           , stratDescr = "Symbolic execution"
           , stratFun   = SolverStrat symbolicFun
           }

-- ----------------------------------------------------------------------------------------
-- Main functions

-- FIXME: define all types etc. eagerly
symbolicFun :: ProvenanceTag -> Slice -> SolverT StrategyM (Maybe SelectedPath)
symbolicFun ptag sl = do
  -- defined referenced types/functions
  reset -- FIXME

  md <- getModule
  slAndDeps <- sliceToDeps sl
  forM_ slAndDeps $ \sl' -> do
    defineSliceTypeDefs md sl'    
    defineSlicePolyFuns sl'    
    defineSliceFunDefs md sl'
    
  scoped $ runSymbolicM $ do
    (_, pathM) <- stratSlice ptag sl
    check -- FIXME: only required if there was no recent 'check' command
    inSolver pathM

-- We need to get types etc for called slices (including root slice)
sliceToDeps :: (Monad m, LiftStrategyM m) => Slice -> m [Slice]
sliceToDeps sl = (:) sl <$> go Set.empty (sliceToCallees sl)
  where
    go seen new
      | Just (n, rest) <- Set.minView new = do
          sl' <- getOne n
          let new' = sliceToCallees sl' `Set.difference` seen
          go (Set.insert n seen) (new' `Set.union` rest)

    go seen _ = mapM getOne (Set.toList seen)

    getOne (f,cl,ev) = getParamSlice f cl ev

-- We return the symbolic value (which may contain bound variables, so
-- those have to be all at the top level) and a computation for
-- constructing the path --- we do it in this way to avoid doing a lot
-- of work that gets thrown away on backtracking, so this gets run
-- once in the final (satisfying) state.  Note that the path
-- construction code shouldn't backtrack, so it could be in (SolverT IO)

type ResultFun = SolverT StrategyM 

stratSlice :: ProvenanceTag -> Slice -> SymbolicM (SemiSExpr, ResultFun SelectedPath)
stratSlice ptag = go
  where
    go sl =  do
      -- liftIO (putStrLn "Slice" >> print (pp sl))
      case sl of
        SDontCare n sl' -> onSlice (fmap (dontCare n)) <$> go sl'
        SDo m_x lsl rsl -> do
          (v, lpath)  <- go lsl
          -- bind name
          onSlice (\rhs -> pathNode <$> (SelectedDo <$> lpath) <*> rhs) <$>
            case m_x of
              Nothing -> go rsl
              Just x  -> bindNameIn x v (go rsl)
              
        SUnconstrained  -> pure (vUnit, pure Unconstrained)
        SLeaf sl'       -> onSlice (fmap (flip pathNode Unconstrained)) <$> goLeaf sl'

    goLeaf sl = do
      -- liftIO (putStr "Leaf: " >> print (pp sl))
      case sl of
        SPure fset e -> do
          tyMap <- getTypeDefs
          uncPath <$> synthesiseExpr (projectE (Just . typeToInhabitant tyMap) fset e)

        SMatch bset -> do
          bname <- vSExpr (TUInt (TSize 8)) <$> inSolver (declareSymbol "b" tByte)
          bassn <- synthesiseByteSet bset bname
          -- This just constrains the byte, we expect it to be satisfiable
          -- (byte sets are typically not empty)
          assert bassn
          -- inSolver check -- required?          
          pure (bname, SelectedBytes ptag . BS.singleton <$> byteModel bname)

        -- SMatch (MatchBytes _e) -> unimplemented sl -- should probably not happen?
        -- SMatch {} -> unimplemented sl

        SAssertion (GuardAssertion e) -> do
          se <- synthesiseExpr e
          assert se
          check
          pure (uncPath vUnit)

        SChoice sls -> do
          (i, sl') <- choose (enumerate sls) -- select a choice, backtracking
          -- liftIO (putStrLn ("Chose " ++ show i)) 
          onSlice (fmap (SelectedChoice i)) <$> go sl'

        SCall cn -> stratCallNode ptag cn

        SCase _ c -> stratCase ptag c

        SInverse n ifn p -> do
          n' <- vSExpr (typeOf n) <$> inSolver (declareName n (symExecTy (typeOf n)))
          pe <- synthesiseExpr p
          assert pe
          check -- FIXME: necessary?

          -- Once we have a model, we need to convert all the free
          -- variables in the inverse function expression into values,
          -- and then call the inverse function in the _interpreter_.
          -- Note that n is free in ifn.
          -- 
          -- We could also have the solver execute the function for
          -- us.
          --
          -- We need to resolve any locally bound variables before we
          -- return the path constructor.

          let fvM = Map.fromSet id $ freeVars ifn
          -- Resolve all Names (to semisexprs and solver names)
          venv <- traverse getName fvM
          pure (n', SelectedBytes ptag <$> applyInverse venv ifn)

    uncPath v = (v, pure (SelectedDo Unconstrained))
    
    applyInverse env ifn = do
      venv <- traverse valueModel env
      ienv <- liftStrategy getIEnv -- for fun defns
      let ienv' = ienv { I.vEnv = venv }
      pure (I.valueToByteString (I.eval ifn ienv'))

    -- unimplemented sl = panic "Unimplemented" [showPP sl]

onSlice :: (ResultFun a -> ResultFun b) ->
           (c, ResultFun a) -> (c, ResultFun b)
onSlice f = \(a, sl') -> (a, f sl')

-- FIXME: maybe name e?
stratCase :: ProvenanceTag -> Case Slice -> SymbolicM (SemiSExpr, ResultFun SelectedNode)
stratCase ptag cs = do
  m_alt <- liftSemiSolverM (semiExecCase cs)
  case m_alt of
    DidMatch i sl -> onSlice (fmap (SelectedCase i)) <$> stratSlice ptag sl
    NoMatch  -> mzero -- just backtrack, no cases matched
    TooSymbolic -> do
      ps <- liftSemiSolverM (symExecToSemiExec (symExecCaseAlts cs))
      (i, (p, sl)) <- choose (enumerate ps)
      assert (vSExpr TBool p)
      check
      onSlice (fmap (SelectedCase i)) <$> stratSlice ptag sl

-- Synthesise for each call 
stratCallNode :: ProvenanceTag -> CallNode -> SymbolicM (SemiSExpr, ResultFun SelectedNode)
stratCallNode ptag CallNode { callName = fn, callClass = cl, callAllArgs = allArgs, callPaths = paths } = do
  -- define all arguments.  We need to evaluate the args in the
  -- current env, as in recursive calls we will have shadowing (in the SolverT env.)
  allUsedArgsV <- traverse synthesiseExpr allUsedArgs
  let binds = Map.toList allUsedArgsV
  flip (foldr (uncurry bindNameIn)) binds $ do
    (_, nonRes) <- unzip <$> mapM doOne asserts
    (v, res)    <- case results of
      [] -> pure (vUnit, pure Unconstrained)
      _  -> do sl <- foldl1' merge <$> mapM (getParamSlice fn cl) results -- merge slices
               stratSlice ptag sl

    pure (v, SelectedCall cl <$> (foldl' merge <$> res <*> sequence nonRes))
  where
    -- This works because 'ResultVar' is < than all over basevars
    (results, asserts) = partition hasResultVar (Set.toList paths)
    doOne ev = do
      sl <- getParamSlice fn cl ev
      stratSlice ptag sl

    -- FIXME: do this as a post-processing step after analysis, once and for all?
    allUsedParams = foldMap programVars paths
    allUsedArgs   = Map.restrictKeys allArgs allUsedParams

-- ----------------------------------------------------------------------------------------
-- Strategy helpers

-- Backtracking choice + random permutation
choose :: (MonadPlus m, LiftStrategyM m) => [a] -> m a
choose bs = do
  bs' <- randPermute bs
  foldr (mplus . pure) doFail bs'
  where
    doFail = do
      -- liftStrategy (liftIO (putStrLn "No more choices"))
      mzero

-- ----------------------------------------------------------------------------------------
-- Solver helpers

liftSemiSolverM :: SemiSolverM StrategyM a -> SymbolicM a
liftSemiSolverM m = do
  funs <- getFunDefs
  lenv <- ask
  env  <- getIEnv  
  inSolver (runSemiSolverM funs lenv env m)  

synthesiseExpr :: Expr -> SymbolicM SemiSExpr
synthesiseExpr = liftSemiSolverM . semiExecExpr

synthesiseByteSet :: ByteSet -> SemiSExpr -> SymbolicM SemiSExpr
synthesiseByteSet bs = liftSemiSolverM . semiExecByteSet bs

check :: SymbolicM ()
check = do
  r <- inSolver Solv.check
  case r of
    S.Sat     -> pure ()
    S.Unsat   -> mzero
    S.Unknown -> mzero

assert :: SemiSExpr -> SymbolicM ()
assert sv =
  case sv of
    VOther p -> inSolver (Solv.assert (typedThing p))
    VValue (I.VBool True) -> pure ()
    VValue (I.VBool False) -> mzero
    _ -> panic "Malformed boolean" [show sv]


-- ----------------------------------------------------------------------------------------
-- Utils

enumerate :: Traversable t => t a -> t (Int, a)
enumerate t = evalState (traverse go t) 0
  where
    go a = state (\i -> ((i, a), i + 1))

inSolver :: SolverT StrategyM a -> SymbolicM a
inSolver = SymbolicM . lift . lift

-- THis all happens after we have finished, so we need to be a bit
-- careful about what is in scope (only thins in the current solver
-- frame, i.e., not do-bound variables.)

byteModel :: SemiSExpr -> SolverT StrategyM Word8
byteModel (VOther symB) = do
  sexp <- Solv.getValue (typedThing symB)
  case evalModelP pByte sexp of
    [] -> panic "No parse" []
    b : _ -> pure b
-- probably shouldn't happen    
byteModel sv = panic "Unimplemented" [show sv]

valueModel :: SemiSExpr -> SolverT StrategyM I.Value
valueModel (VValue v)    = pure v
valueModel sv =
  SE.toValue <$> traverse go sv
  where
    go tse = do
      sexp <- Solv.getValue (typedThing tse)
      case evalModelP (pValue (typedType tse)) sexp of
        [] -> panic "No parse" []
        v : _ -> pure v












