{-# Language BlockArguments #-}
{-# Language OverloadedStrings #-}
{-# Language ViewPatterns #-}
{-# Language DeriveGeneric, DeriveAnyClass #-}
{-# Language DeriveTraversable #-}

module Daedalus.Core.Basics where

import Control.DeepSeq (NFData)
import GHC.Generics (Generic)

import Data.Text(Text)
import Data.Function(on)

import Daedalus.PP
import Daedalus.GUID

-- | Module names
newtype MName = MName { mNameText :: Text }
  deriving (Eq,Ord,Generic,NFData)

-- | Type declaration names
data TName = TName
  { tnameId   :: GUID
  , tnameText :: Text
  , tnameMod  :: MName
  , tnameAnon :: Maybe Int    -- ^ For types that only appear in other types
  , tnameRec  :: Bool         -- ^ Is this type part of a recursive group
  , tnameBD   :: !Bool        -- ^ Is this a bitdata type
  , tnameFlav :: TFlav        -- ^ Some information about the type
  }
  deriving (Generic, NFData)

-- | What "flavor of type" we have
data TFlav = TFlavStruct
           | TFlavEnum  [Label]      -- ^ A sum type with no data
           | TFlavUnion [Label]      -- ^ A sum type with data
           deriving (Generic, NFData)

-- | Names of top-level functions
data FName = FName
  { fnameId         :: GUID
  , fnameText       :: Maybe Text
  , fnameType       :: Type
  , fnameMod        :: MName
  }
  deriving (Generic, NFData)

-- | Names of local variables
data Name = Name
  { nameId   :: GUID
  , nameText :: Maybe Text      -- ^ Name in source, if any
  , nameType :: Type
  }
  deriving (Generic, NFData)


-- | Annotation
data Annot =
    SrcAnnot Text
  | NoFail          -- ^ The grammar is known to not fail
  deriving (Generic,NFData)

type Label = Text

data Type =
    TStream
  | TUInt SizeType
  | TSInt SizeType
  | TInteger
  | TBool
  | TFloat
  | TDouble
  | TUnit
  | TArray Type
  | TMaybe Type
  | TMap Type Type
  | TBuilder Type         -- ^ Builder for arrays
  | TIterator Type
  | TUser UserType
  | TParam TParam         -- ^ Only in type declaraionts
    deriving (Eq,Ord,Generic,NFData)

data SizeType =
    TSize Integer
  | TSizeParam TParam     -- ^ Only in type declarations
  deriving (Eq,Ord,Generic,NFData)

data UserType = UserType
  { utName    :: TName
  , utNumArgs :: [SizeType]
  , utTyArgs  :: [Type]
  } deriving (Eq,Ord,Generic,NFData)


newtype TParam = TP Int
  deriving (Eq,Ord,Generic,NFData)

data Case k = Case Name [(Pattern,k)]
  deriving (Functor,Foldable,Traversable,Generic,NFData)

data Pattern =
    PBool Bool
  | PNothing
  | PJust
  | PNum Integer
  | PCon Label
  | PAny
    deriving (Eq,Ord,Generic,NFData)

-- A convenience type for typed things
data Typed a = Typed
  { typedType :: Type
  , typedThing :: a
  }
  deriving (Eq,Ord,Generic,NFData)

instance Show a => Show (Typed a) where
  show = show . typedThing

--------------------------------------------------------------------------------
-- Convenience functions

isBits :: Type -> Maybe (Bool, Integer)
isBits (isUInt -> Just n) = Just (False, n)
isBits (isSInt -> Just n) = Just (True, n)
isBits _                  = Nothing

isUInt :: Type -> Maybe Integer
isUInt (TUInt (TSize n)) = Just n
isUInt _                 = Nothing

isSInt :: Type -> Maybe Integer
isSInt (TSInt (TSize n)) = Just n
isSInt _                 = Nothing


--------------------------------------------------------------------------------
freshTName :: HasGUID m => TName -> m TName
freshTName n =
  do x <- getNextGUID
     pure n { tnameId = x }

freshFName :: HasGUID m => FName -> m FName
freshFName n =
  do x <- getNextGUID
     pure n { fnameId = x }

freshName :: HasGUID m => Name -> m Name
freshName n =
  do x <- getNextGUID
     pure n { nameId = x }

freshNameSys :: HasGUID m => Type -> m Name
freshNameSys t =
  do x <- getNextGUID
     pure Name { nameId = x, nameType = t, nameText = Nothing }

--------------------------------------------------------------------------------
instance Eq Name where
  (==) = (==) `on` nameId

instance Ord Name where
  compare = compare `on` nameId

instance Eq FName where
  (==) = (==) `on` \x -> (fnameId x, fnameMod x)

instance Ord FName where
  compare = compare `on` \x -> (fnameId x, fnameMod x)

instance Eq TName where
  (==) = (==) `on` tnameId

instance Ord TName where
  compare = compare `on` tnameId


--------------------------------------------------------------------------------

instance PP MName where
  pp (MName x) = pp x

instance PP TName where
  pp t = pp (tnameText t) <.> maybe empty pp (tnameAnon t)

instance PP FName where
  pp f = case fnameText f of
           Nothing -> "_F" <.> pp (fnameId f)
           Just t  -> pp t


instance PP Name where
  pp n = case nameText n of
           Nothing -> "_x" <.> pp (nameId n)
           Just t  -> pp t


instance PP Annot where
  pp ann =
    case ann of
      SrcAnnot t -> pp t
      NoFail     -> "NoFail"


instance PP Type where
  ppPrec n ty =
    case ty of
      TStream     -> "Input"
      TUInt w     -> wrapIf (n > 0) ("Word" <+> pp w)
      TSInt w     -> wrapIf (n > 0) ("Int" <+> pp w)
      TInteger    -> "Integer"
      TBool       -> "Bool"
      TFloat      -> "Float"
      TDouble     -> "Double"
      TUnit       -> "()"
      TArray t    -> brackets (pp t)
      TMap k v    -> brackets (pp k <+> "->" <+> pp v)
      TMaybe t    -> wrapIf (n > 0) ("Maybe" <+> ppPrec 1 t)
      TBuilder t  -> wrapIf (n > 0) ("Builder" <+> ppPrec 1 t)
      TIterator t -> wrapIf (n > 0) ("Iter" <+> ppPrec 1 t)
      TUser t     -> pp t
      TParam x    -> pp x

instance PP UserType where
  ppPrec n t =
    case (utNumArgs t, utTyArgs t) of
      ([],[]) -> pp (utName t)
      _       -> wrapIf (n > 0)
               $ hsep [ pp (utName t)
                      , hsep (map pp (utNumArgs t))
                      , hsep (map (ppPrec 1) (utTyArgs t))
                      ]

instance PP TParam where
  pp (TP x) = "?t" <.> pp x

instance PP SizeType where
  pp t =
    case t of
      TSize n -> pp n
      TSizeParam x -> pp x

instance PP a => PP (Case a) where
  pp (Case e as) = "case" <+> pp e <+> "of" $$ nest 2 (vcat (map alt as))
    where
    alt (p,g) = pp p <+> "->" $$ nest 2 (pp g)

instance PP Pattern where
  pp pat =
    case pat of
      PBool  b  -> pp b
      PNothing  -> "nothing"
      PJust     -> "just"
      PNum   n  -> pp n
      PCon   l  -> pp l
      PAny      -> "_"
