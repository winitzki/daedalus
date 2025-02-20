{-# Language OverloadedStrings #-}
module Daedalus.VM.Backend.C.Types where

import Text.PrettyPrint as P

import Daedalus.PP
import Daedalus.Panic(panic)
import Daedalus.VM
import qualified Daedalus.Core as Src

import Daedalus.VM.Backend.C.Lang
import Daedalus.VM.Backend.C.Names


cType :: VMT -> CType
cType ty =
  case ty of
    TThreadId -> "DDL::ThreadId"
    TSem sty  -> cSemType sty

cSemType :: Src.Type -> Doc
cSemType sty =
  case sty of
    Src.TStream     -> "DDL::Input"
    Src.TUInt n     -> cInst "DDL::UInt" [ cSizeType n ]
    Src.TSInt n     -> cInst "DDL::SInt" [ cSizeType n ]
    Src.TInteger    -> "DDL::Integer"
    Src.TBool       -> "DDL::Bool"
    Src.TFloat      -> "DDL::Float"
    Src.TDouble     -> "DDL::Double"
    Src.TUnit       -> "DDL::Unit"
    Src.TArray t    -> cInst "DDL::Array" [ cSemType t ]
    Src.TMaybe t    -> cInst "DDL::Maybe" [ cSemType t ]
    Src.TMap k v    -> cInst "DDL::Map" [ cSemType k, cSemType v ]
    Src.TBuilder t  -> cInst "DDL::Array" [ cSemType t ] <.> "::Builder"

    Src.TIterator t ->
      case t of
        Src.TArray a  -> cInst "DDL::Array" [ cSemType a ] <.> "::Iterator"
        Src.TMap k v  -> cInst "DDL::Map" [ cSemType k, cSemType v]
                                                          <.> "::Iterator"
        _ -> panic "cSemType" [ "Unexpected iterator type", show (pp t) ]
    Src.TUser ut               -> cTUser ut
    Src.TParam a               -> cTParam a -- can happen in types

cSizeType :: Src.SizeType -> CType {- ish -}
cSizeType ty =
  case ty of
    Src.TSize n      -> integer n
    Src.TSizeParam x -> cTParam x -- in types

cTUser :: Src.UserType -> CType
cTUser t = cTypeUse (cTNameUse GenPublic (Src.utName t))
                    (map cSizeType (Src.utNumArgs t))
                    (map cSemType (Src.utTyArgs t))

cTypeUse :: Doc -> [Doc] -> [Doc] -> CType
cTypeUse nm nparams vparams =
  case nparams ++ vparams of
    [] -> nm
    xs -> nm <.> "<" <.> hsep (punctuate comma xs) <.> ">"

