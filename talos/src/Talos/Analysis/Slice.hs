{-# LANGUAGE GADTs, DataKinds, RankNTypes, PolyKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric, DeriveAnyClass, DefaultSignatures #-}

-- Path set analysis


module Talos.Analysis.Slice where

import Control.Applicative ((<|>))
import Data.Function (on)
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Foldable (fold)

import Control.DeepSeq (NFData)
import GHC.Generics (Generic)

import Daedalus.PP
import Daedalus.Panic

import Daedalus.Core
import Daedalus.Core.Free
import Daedalus.Core.TraverseUserTypes

import Talos.Analysis.EntangledVars
import Talos.Analysis.Projection (projectE)

-- import Debug.Trace

--------------------------------------------------------------------------------
-- Representation of paths/pathsets
-- smart constructor for dontCares.

sDontCare :: Int -> Slice -> Slice
sDontCare 0 sl = sl
sDontCare  n (SDontCare m ps)   = SDontCare (n + m) ps
sDontCare _n SUnconstrained = SUnconstrained
sDontCare n  ps = SDontCare n ps

--------------------------------------------------------------------------------
-- Slices

data Assertion = GuardAssertion Expr
  deriving (Generic, NFData)

-- This is the class of summary for a function; 'Assertions' summaries
-- contain information internal to the function, while
-- 'FunctionResult' also includes information about the return value.
-- These are used when the result of a function is non used and when
-- it is, resp.
--
-- In practice 'FunctionResult' will be a superset of 'Assertions'
--
-- We could compute both (simultaneously?) but for the most part only
-- 'Assertions' will be required.
data SummaryClass = Assertions | FunctionResult (Set FieldSet)
  deriving (Ord, Eq, Show, Generic, NFData)

-- data CallInstance =
--   CallInstance { callParams :: EntangledVars
--                -- ^ Set of params (+ result) free in the slice, used to call the model function in SMT

--               -- , callSlice  :: Slice
--                -- ^ The slice inside the function
--                }

-- We represent a Call by a set of the entangled args.  If the
-- args aren't futher entangled by the calling context, then for
-- each argument slice we get a single Call node, where the Set is a
-- singleton containing the representative var as returned by
-- 'explodeDomain'.  The second argument tells us how to instantiate
-- the params used by the call.
--
-- We require a set so we can merge where the callers entangle params.
--
-- The first argument is whether this call is an assigned, in which
-- case the entangled vars must contain ResultVar.  Note that the
-- first argument can also be ResultVar, but that is the result of
-- the current function, not this call (e.g. def Foo = { ...; Bar })
--
-- Note that the set of entangled vars here is a bit different to
-- that which appears in a Domain, if only in intent --- these are
-- entangled by their context, while in a domain they are entangled
-- by use

-- def F x y = { Guard (x > 10); Guard (y > 10); ^ 42 }
--
-- def Q = { a = UInt8; z = F a a; Guard (z > 10); ^ true } -- entangles x and y above
--
-- F will generate slices for 'x', 'y', and the result, but at Q we
-- entangle 'x' and 'y' through 'a'

data CallNode =
  CallNode { callClass        :: SummaryClass
           , callAllArgs      :: Map Name Expr
           -- ^ A shared map (across all domain elements) of the args to the call
           , callName         :: FName
           -- ^ The called function

           , callPaths        :: Set EntangledVars -- Map EntangledVar CallInstance

           -- ^ All entangled params for the call, the range (wrapped)
           -- are in the _callee_'s namespace, so we don't merge etc.
           }
  deriving (Generic, NFData)

-- We assume the core has been simplified (no nested do etc.)
data Slice =
  -- Sequencing
  SDontCare Int Slice
  | SDo (Maybe Name) Slice Slice -- We merge Do and Do_
  -- Terminals
  | SUnconstrained -- shorthand for 'SDontCare \infty (SLeaf (SPure VUnit))'
  | SLeaf SliceLeaf
  deriving (Generic, NFData)

-- A note on inverses.  The ides is if we have something like
--
-- def F y = {
--   x = UInt8 # UInt8 # UInt8 # UInt 8
--   Guard (x > y && x < 1000)
--   ^ x
-- }
--
-- we can replace calls to F (in slices) like
--
-- ...
-- v = F y
-- ...
-- 
-- with (\result > y && \result < 1000) when synthesising, and then
-- [\result >> 24 as uint 8, \result >> 16 as uint 8, \result >> 8 as uint 8, \result as uint 8 ]
-- when constructing the path (i.e., when getting bytes).

-- These are the supported leaf nodes -- we could just reuse Grammar but it
-- is nice to be explicit here.
data SliceLeaf =
  SPure FieldSet Expr    -- ^ FieldSet tells us which bits of the Expr we care about.
  | SMatch ByteSet       -- ^ Match a byte
  | SAssertion Assertion -- FIXME: this is inferred from e.g. case x of True -> ...
  | SChoice [Slice] -- ^ we represent all choices as a n-ary node, not a tree of binary nodes
  | SCall CallNode
  | SCase Bool (Case Slice)
  -- FIXME: we may want to return a list of predicates when they are
  -- disjoint (so we get mutiple slices), but this may be tricky and
  -- not warranted.
  | SInverse Name Expr Expr
  -- ^ We have an inverse for this statement; this constructor has a
  -- name for the result (considered bound in this term only), the
  -- inverse expression, and a predicate constraining the value
  -- produced by this node (i.e., result of the original DDL code).
  deriving (Generic, NFData)

--------------------------------------------------------------------------------
-- Domain Instances

-- This assumes the node came from the same statement (i.e., the paths
-- we are comparing are rooted at the same statement).  This means we
-- don't need to compare for equality.
--
-- Thus, for some cases, the presence of a node is enough to return
-- True (e.g. for Assertion)

class Eqv a where
  eqv :: a -> a -> Bool
  default eqv :: Eq a => a -> a -> Bool
  eqv = (==)

instance Eqv Int
instance Eqv Integer
instance Eqv SummaryClass

instance (Eqv a, Eqv b) => Eqv (a, b) where
  eqv (a, b) (a', b') = a `eqv` a' && b `eqv` b'

instance Eqv Slice where
  eqv l r =
    case (l, r) of
      (SDontCare n rest, SDontCare m rest') -> (m, rest) `eqv` (n, rest')

      (SDo _x slL1 slR1, SDo _x' slL2 slR2) -> (slL1, slR1) `eqv` (slL2, slR2)

      (SUnconstrained, SUnconstrained) -> True
      (SLeaf sl1, SLeaf sl2) -> sl1 `eqv` sl2

      _ -> False -- panic "Comparing non-comparable nodes" [showPP l, showPP r]

instance Eqv SliceLeaf where
  eqv l r =
    case (l, r) of
      (SPure fset _, SPure fset' _)  -> fset == fset'
      (SMatch {}, SMatch {})         -> True
      (SAssertion {}, SAssertion {}) -> True
      (SChoice ls, SChoice rs)       -> all (uncurry eqv) (zip ls rs)
      (SCall lc, SCall rc)           -> lc `eqv` rc
      (SCase _ lc, SCase _ rc)       -> lc `eqv` rc
      (SInverse {}, SInverse {})       -> True
      _                              -> panic "Mismatched terms in eqvSliceLeaf" ["Left", showPP l, "Right", showPP r]

instance Eqv CallNode where
  eqv CallNode { callClass = cl1, callPaths = paths1 }
      CallNode { callClass = cl2, callPaths = paths2 } =
    -- trace ("Eqv " ++ showPP cn ++ " and " ++ showPP cn') $
    cl1 == cl2 && paths1 == paths2

-- instance Eqv CallInstance where
--   eqv (CallInstance { callParams = ps1 {- , callSlice = sl1 -} })
--       (CallInstance { callParams = ps2 {- , callSlice = sl2 -} }) =
--     ps1 == ps2 -- && eqv sl1 sl2

instance Eqv a => Eqv (Case a) where
  eqv (Case _e alts1) (Case _e' alts2) =
    all (uncurry $ on eqv snd) (zip alts1 alts2)

-- Merging
--
-- Similar to a semigroup, but with more restrictions about how it can
-- be used (i.e., the merged objects come from the same program)

class Merge a where
  merge :: a -> a -> a

instance Merge CallNode where
  merge cn@CallNode { callClass = cl1, callPaths = paths1 }
           CallNode { callClass = cl2, callPaths = paths2 }
    | cl1 /= cl2 = panic "Saw different function classes" []
    -- FIXME: check that the sets don't overlap
    | otherwise =
      -- trace ("Merging " ++ showPP cn ++ " and " ++ showPP cn') $
      cn { callPaths = Set.union paths1 paths2 }

-- instance Merge CallInstance where
--   merge (CallInstance { callParams = ps1 {- , callSlice = sl1 -} })
--         (CallInstance { callParams = ps2 {- , callSlice = sl2 -} }) =
--     CallInstance { callParams = mergeEntangledVars ps1 ps2 {- , callSlice = merge sl1 sl2 -} }

instance Merge a => Merge (Case a) where
  merge (Case e alts1) (Case _e alts2) = Case e (zipWith goAlt alts1 alts2)
    where
      goAlt (p, a1) (_p, a2) = (p, merge a1 a2)


instance Merge SliceLeaf where
  merge l r =
    case (l, r) of
      (SPure fset e, SPure fset' _e) -> SPure (fset <> fset') e
      (SMatch {}, SMatch {})         -> l
      (SAssertion {}, SAssertion {}) -> l
      (SChoice cs1, SChoice cs2)     -> SChoice (zipWith merge cs1 cs2)
      (SCall lc, SCall rc)           -> SCall (merge lc rc)
      (SCase t lc, SCase _ rc)       -> SCase t (merge lc rc)
      (SInverse {}, SInverse{})      -> l
      _                              -> panic "Mismatched terms in merge"
                                              ["Left", showPP l, "Right", showPP r]

-- This assumes the slices come from the same program, i.e., simple
-- slices should be identical.
instance Merge Slice where
  merge l r =
    case (l, r) of
      (_, SUnconstrained)            -> l
      (SUnconstrained, _)            -> r

      (SDontCare 0 rest, _)          -> merge rest r -- Shouldn't happen.
      (SDontCare n rest, SDontCare m rest') ->
        let count = min m n
        in sDontCare count (merge (sDontCare (n - count) rest) (sDontCare (m - count) rest'))
      (SDontCare n rest, SDo m_x slL slR) -> SDo m_x slL (merge (sDontCare (n - 1) rest) slR)

      -- FIXME: does this make sense?
      (SDontCare n rest, sl) -> SDo Nothing sl (sDontCare (n - 1) rest)

      (_, SDontCare {})       -> merge r l

      (SDo x1 slL1 slR1, SDo x2 slL2 slR2) ->
        SDo (x1 <|> x2) (merge slL1 slL2) (merge slR1 slR2)

      -- This happens due to the way we construct nodes
      (SDo x slL slR, SLeaf sl) -> SDo x (merge slL (SLeaf sl)) slR

      (_, SDo {})               -> merge r l

      (SLeaf sl1, SLeaf sl2) -> SLeaf (merge sl1 sl2)


--------------------------------------------------------------------------------
-- Called slices
--

sliceToCallees :: Slice -> Set (FName, SummaryClass, EntangledVars)
sliceToCallees = go
  where
    go sl = case sl of
      SDontCare _ sl'   -> go sl'
      SDo _ l r         -> go l <> go r
      SUnconstrained    -> mempty
      SLeaf l           -> goLeaf l

    goLeaf l = case l of
      SPure {}      -> mempty
      SMatch _m     -> mempty
      SAssertion _e -> mempty
      SChoice cs    -> foldMap go cs
      SCall cn      -> Set.map (\evs -> (callName cn, callClass cn, evs)) (callPaths cn)
      SCase _ c     -> foldMap go c
      SInverse {}   -> mempty -- No grammar calls

--------------------------------------------------------------------------------
-- Free instances
--
--  Used for getting deps for the SMT solver defs.

instance FreeVars Slice where
  freeVars sl =
    case sl of
      SDontCare _ sl'   -> freeVars sl'
      SDo Nothing  l r  -> freeVars l <> freeVars r
      SDo (Just x) l r  -> freeVars l <> Set.delete x (freeVars r)
      SUnconstrained    -> mempty
      SLeaf s           -> freeVars s

  freeFVars sl =
    case sl of
      SDontCare _ sl' -> freeFVars sl'
      SDo _ l r       -> freeFVars l <> freeFVars r
      SUnconstrained  -> mempty
      SLeaf s         -> freeFVars s

instance FreeVars SliceLeaf where
  freeVars sl =
    case sl of
      SPure _ v      -> freeVars v -- FIXME: ignores fset, which night not be what we want
      SMatch m       -> freeVars m
      SAssertion e   -> freeVars e
      SChoice cs     -> foldMap freeVars cs
      SCall cn       -> freeVars cn
      SCase _ c      -> freeVars c
      SInverse n f p -> Set.delete n (freeVars f <> freeVars p)

  freeFVars sl =
    case sl of
      SPure _ v      -> freeFVars v
      SMatch m       -> freeFVars m
      SAssertion e   -> freeFVars e
      SChoice cs     -> foldMap freeFVars cs
      SCall cn       -> freeFVars cn
      SCase _ c      -> freeFVars c
      -- the functions in f should not be e.g. sent to the solver
      -- FIXME: what about other usages of this function?
      SInverse _ f p -> {- freeFVars f <> -} freeFVars p 

callNodeActualArgs :: CallNode -> Map Name Expr
callNodeActualArgs cn =
  Map.restrictKeys (callAllArgs cn) usedParams
  where
    usedEVParams = fold (callPaths cn)
    usedParams   = programVars usedEVParams

instance FreeVars CallNode where
  freeVars cn  = foldMap freeVars (Map.elems (callNodeActualArgs cn))
  freeFVars cn = Set.insert (callName cn) (foldMap freeFVars (Map.elems (callNodeActualArgs cn)))

instance FreeVars Assertion where
  freeVars  (GuardAssertion e) = freeVars e
  freeFVars (GuardAssertion e) = freeFVars e


-- -----------------------------------------------------------------------------
-- FreeTCons
traverseUserTypesMap :: (Ord a, TraverseUserTypes a, TraverseUserTypes b, Applicative f) =>
                        (UserType -> f UserType) -> Map a b -> f (Map a b)
traverseUserTypesMap f = fmap Map.fromList . traverseUserTypes f . Map.toList

instance TraverseUserTypes Slice where
  traverseUserTypes f sl =
    case sl of
      SDontCare n sl'   -> SDontCare n <$> traverseUserTypes f sl'
      SDo m_x l r       -> SDo <$> traverseUserTypes f m_x <*> traverseUserTypes f l <*> traverseUserTypes f r
      SUnconstrained    -> pure sl
      SLeaf s           -> SLeaf <$> traverseUserTypes f s

instance TraverseUserTypes SliceLeaf where
  traverseUserTypes f sl =
    case sl of
      SPure fset v     -> SPure fset <$> traverseUserTypes f v
      SMatch m         -> SMatch <$> traverseUserTypes f m
      SAssertion e     -> SAssertion <$> traverseUserTypes f e
      SChoice cs       -> SChoice <$> traverseUserTypes f cs
      SCall cn         -> SCall   <$> traverseUserTypes f cn
      SCase b c        -> SCase b <$> traverseUserTypes f c
      SInverse n ifn p -> SInverse n <$> traverseUserTypes f ifn <*> traverseUserTypes f p

instance TraverseUserTypes CallNode where
  traverseUserTypes f cn  =
    (\args' n' paths' -> cn { callAllArgs = args', callName = n', callPaths = paths'  })
    <$> traverseUserTypesMap f (callNodeActualArgs cn)
    <*> traverseUserTypes f (callName cn)
    <*> traverseUserTypes f (callPaths cn)

-- instance TraverseUserTypes CallInstance where
--   traverseUserTypes f ci  =
--     CallInstance <$> traverseUserTypes f (callParams ci) -- <*> traverseUserTypes f (callSlice ci)

instance TraverseUserTypes Assertion where
  traverseUserTypes f (GuardAssertion e) = GuardAssertion <$> traverseUserTypes f e

--------------------------------------------------------------------------------
-- PP Instances

-- instance PP CallInstance where
--   ppPrec n (CallInstance { callParams = ps, callSlice = sl }) =
--     wrapIf (n > 0) $ pp ps <+> "-->" <+> pp sl

instance PP CallNode where
  ppPrec n CallNode { callName = fname, callPaths = evs } =
        wrapIf (n > 0) $ ("call " <> pp fname)
                                  <+> (lbrace <> commaSep (map pp (Set.toList evs)) <> rbrace)

instance PP SliceLeaf where
  ppPrec n sl =
    case sl of
      SPure fset v -> wrapIf (n > 0) $ "pure" <+> ppPrec 1 (projectE (const Nothing) fset v)
      SMatch m -> wrapIf (n > 0) $ "match" <+> pp m
      SAssertion e -> wrapIf (n > 0) $ "assert" <+> ppPrec 1 e
      SChoice cs    -> "choice" <> block "{" "," "}" (map pp cs)
      SCall cn -> ppPrec n cn
      SCase _ c -> pp c
      SInverse n' ifn p -> wrapIf (n > 0) $ "inverse for" <+> ppPrec 1 n' <+> "is" <+> ppPrec 1 ifn <+> "/" <+> ppPrec 1 p

ppStmt :: Slice -> Doc
ppStmt sl =
  case sl of
    SDo (Just x) e1 e2 -> (pp x <+> "<-" <+> pp e1) $$ ppStmt e2
    SDo Nothing  e1 e2 ->                    pp e1  $$ ppStmt e2
    _           -> pp sl

instance PP Slice where
  ppPrec n ps =
    case ps of
      SDontCare 1 sl  -> wrapIf (n > 0) $ "[..]; " <> pp sl
      SDontCare n' sl -> wrapIf (n > 0) $ "[..]"   <> pp n' <> "; " <> pp sl
      SDo  {}         -> "do" <+> ppStmt ps

      SUnconstrained -> "[..]*;"
      SLeaf s     -> ppPrec n s

instance PP Assertion where
  pp (GuardAssertion g) = pp g

instance PP SummaryClass where
  pp Assertions     = "Assertions"
  pp (FunctionResult fs) = "Result" <+> (lbrace <> commaSep (map pp (Set.toList fs)) <> rbrace)

