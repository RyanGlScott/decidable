{-# LANGUAGE EmptyCase             #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE GADTs                 #-}
{-# LANGUAGE InstanceSigs          #-}
{-# LANGUAGE LambdaCase            #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE RankNTypes            #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE StandaloneDeriving    #-}
{-# LANGUAGE TypeApplications      #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE TypeInType            #-}
{-# LANGUAGE TypeOperators         #-}
{-# LANGUAGE TypeSynonymInstances  #-}
{-# LANGUAGE UndecidableInstances  #-}

module Data.Type.Universe (
    Elem
  , Universe(..), decideAny, decideAll, genAllA, genAll, igenAll
  , foldMapUni, ifoldMapUni, select, pickElem
  , All, WitAll(..)
  , Any, WitAny(..)
  , Index(..), IsJust(..), IsRight(..), NEIndex(..), Snd(..)
  , Null, NotNull
  ) where

import           Control.Applicative
import           Data.Functor.Identity
import           Data.Kind
import           Data.List.NonEmpty                    (NonEmpty(..))
import           Data.Singletons
import           Data.Singletons.Decide
import           Data.Singletons.Prelude hiding        (Elem, Any, All, Snd, Null, Not)
import           Data.Type.Predicate
import           Prelude hiding                        (any, all)
import qualified Data.Singletons.Prelude.List.NonEmpty as NE

-- | A witness for membership of a given item in a type-level collection
type family Elem      (f :: Type -> Type) :: f k -> k -> Type

-- | An @'Any' p as@ is a witness that, for at least one item @a@ in the
-- type-level collection @as@, the predicate @p a@ is true.
data WitAny f :: (k ~> Type) -> f k -> Type where
    WitAny :: Elem f as a -> p @@ a -> WitAny f p as

data Any f :: (k ~> Type) -> (f k ~> Type)
type instance Apply (Any f p) as = WitAny f p as

-- | An @'All' p as@ is a witness that, the predicate @p a@ is true for all
-- items @a@ in the type-level collection @as@.
newtype WitAll f p (as :: f k) = WitAll { runWitAll :: forall a. Elem f as a -> p @@ a }

data All f :: (k ~> Type) -> (f k ~> Type)
type instance Apply (All f p) as = WitAll f p as

instance (Universe f, Decide p) => Decide (Any f p) where
    decide = decideAny @f @_ @p $ decide @p

instance (Universe f, Decide p) => Decide (All f p) where
    decide = decideAll @f @_ @p $ decide @p

instance (Universe f, Decide_ p) => Decide_ (All f p) where
    decide_ xs = WitAll $ \i -> decide_ @p (select i xs)

instance Universe f => TFunctor (Any f) where
    tmap f xs (WitAny i x) = WitAny i (f (select i xs) x)

instance Universe f => TFunctor (All f) where
    tmap f xs a = WitAll $ \i -> f (select i xs) (runWitAll a i)

instance Universe f => DFunctor (All f) where
    dmap f xs a = idecideAll (\i x -> f x (runWitAll a i)) xs

-- | Typeclass for a type-level container that you can quantify or lift
-- type-level predicates over.
class Universe (f :: Type -> Type) where

    -- | You should read this type as:
    --
    -- @
    -- 'decideAny'' :: ('Sing' a  -> 'Decision' (p a)    )
    --            -> (Sing as -> Decision (Any p as)
    -- @
    --
    -- It lifts a predicate @p@ on an individual @a@ into a predicate that
    -- on a collection @as@ that is true if and only if /any/ item in @as@
    -- satisfies the original predicate.
    --
    -- That is, it turns a predicate of kind @k ~> Type@ into a predicate
    -- of kind @f k ~> Type@.
    --
    -- Essentially tests existential quantification.
    idecideAny
        :: forall k (p :: k ~> Type) (as :: f k). ()
        => (forall a. Elem f as a -> Sing a -> Decision (p @@ a))   -- ^ predicate on value
        -> (Sing as -> Decision (Any f p @@ as))                         -- ^ predicate on collection

    -- | You should read this type as:
    --
    -- @
    -- 'decideAll'' :: ('Sing' a  -> 'Decision' (p a)    )
    --            -> ('Sing' as -> 'Decision' (All p as)
    -- @
    --
    -- It lifts a predicate @p@ on an individual @a@ into a predicate that
    -- on a collection @as@ that is true if and only if /all/ items in @as@
    -- satisfies the original predicate.
    --
    -- That is, it turns a predicate of kind @k ~> Type@ into a predicate
    -- of kind @f k ~> Type@.
    --
    -- Essentially tests universal quantification.
    idecideAll
        :: forall k (p :: k ~> Type) (as :: f k). ()
        => (forall a. Elem f as a -> Sing a -> Decision (p @@ a))   -- ^ predicate on value
        -> (Sing as -> Decision (All f p @@ as))                         -- ^ predicate on collection

    -- | If @p a@ is true for all values @a@ in @as@ under some
    -- (Applicative) context @h@, then you can create an @'All' p as@ under
    -- that Applicative context @h@.
    --
    -- Can be useful with 'Identity' (which is basically unwrapping and
    -- wrapping 'All'), or with 'Maybe' (which can express predicates that
    -- are either provably true or not provably false).
    igenAllA
        :: forall k (p :: k ~> Type) (as :: f k) h. Applicative h
        => (forall a. Elem f as a -> Sing a -> h (p @@ a))        -- ^ predicate on value in context
        -> (Sing as -> h (All f p @@ as))                              -- ^ predicate on collection in context

type Null    f = (Not (NotNull f) :: Predicate (f k))
type NotNull f = (Any f Evident :: Predicate (f k))

decideAny
    :: forall f k (p :: k ~> Type). Universe f
    => Test p                                 -- ^ predicate on value
    -> Test (Any f p)                -- ^ predicate on collection
decideAny f = idecideAny (const f)

decideAll
    :: forall f k (p :: k ~> Type). Universe f
    => Test p                                 -- ^ predicate on value
    -> Test (All f p)                -- ^ predicate on collection
decideAll f = idecideAll (const f)

-- | 'igenAllA', but without the membership witness.
genAllA
    :: forall k (p :: k ~> Type) (as :: f k) h. (Universe f, Applicative h)
    => (forall a. Sing a -> h (p @@ a))        -- ^ predicate on value in context
    -> (Sing as -> h (All f p @@ as))               -- ^ predicate on collection in context
genAllA f = igenAllA (const f)

-- | If @p a@ is true for all values @a@ in @as@, then we have @'All'
-- p as@.  Basically witnesses the definition of 'All'.
igenAll
    :: forall f k (p :: k ~> Type) (as :: f k). Universe f
    => (forall a. Elem f as a -> Sing a -> p @@ a)            -- ^ always-true predicate on value
    -> (Sing as -> All f p @@ as)                                  -- ^ always-true predicate on collection
igenAll f = runIdentity . igenAllA (\i -> Identity . f i)

genAll
    :: forall f k (p :: k ~> Type). Universe f
    => Test_ p                          -- ^ always-true predicate on value
    -> Test_ (All f p)         -- ^ always-true predicate on collection
genAll f = igenAll (const f)

-- | Extract the item from the container witnessed by the 'Elem'
select
    :: forall f as a. Universe f
    => Elem f as a        -- ^ Witness
    -> Sing as            -- ^ Collection
    -> Sing a
select i = (`runWitAll` i) . splitSing

-- | Split a @'Sing' as@ into a proof that all @a@ in @as@ exist.
splitSing
    :: forall f (as :: f k). Universe f
    => Sing as
    -> All f (TyPred Sing) @@ as
splitSing = igenAll @f @_ @(TyPred Sing) (\_ x -> x)

-- | Automatically generate a witness for a member, if possible
pickElem
    :: forall f k (as :: f k) a. (Universe f, SingI as, SingI a, SDecide k)
    => Decision (Elem f as a)
pickElem = case decide @(Any f (TyPred ((:~:) a))) sing of
    Proved (WitAny i Refl) -> Proved i
    Disproved v            -> Disproved $ \i -> v $ WitAny i Refl

-- | 'foldMapUni' but with access to the index.
ifoldMapUni
    :: forall f k (as :: f k) m. (Universe f, Monoid m)
    => (forall a. Elem f as a -> Sing a -> m)
    -> Sing as
    -> m
ifoldMapUni f = getConst . igenAllA (\i -> Const . f i)

-- | A 'foldMap' over all items in a collection.
foldMapUni
    :: forall f k (as :: f k) m. (Universe f, Monoid m)
    => (forall (a :: k). Sing a -> m)
    -> Sing as
    -> m
foldMapUni f = ifoldMapUni (const f)

-- | Witness an item in a type-level list by providing its index.
data Index :: [k] -> k -> Type where
    IZ :: Index (a ': as) a
    IS :: Index bs a -> Index (b ': bs) a

deriving instance Show (Index as a)
instance (SingI (as :: [k]), SDecide k) => Decide (TyPred (Index as)) where
    decide x = withSingI x $ pickElem

type instance Elem [] = Index

instance Universe [] where
    idecideAny
        :: forall k (p :: k ~> Type) (as :: [k]). ()
        => (forall a. Elem [] as a -> Sing a -> Decision (p @@ a))
        -> Sing as
        -> Decision (Any [] p @@ as)
    idecideAny f = \case
      SNil -> Disproved $ \case
        WitAny i _ -> case i of {}
      x `SCons` xs -> case f IZ x of
        Proved p    -> Proved $ WitAny IZ p
        Disproved v -> case idecideAny @[] @_ @p (f . IS) xs of
          Proved (WitAny i p) -> Proved $ WitAny (IS i) p
          Disproved vs -> Disproved $ \case
            WitAny IZ     p -> v p
            WitAny (IS i) p -> vs (WitAny i p)

    idecideAll
        :: forall k (p :: k ~> Type) (as :: [k]). ()
        => (forall a. Elem [] as a -> Sing a -> Decision (p @@ a))
        -> Sing as
        -> Decision (All [] p @@ as)
    idecideAll f = \case
      SNil -> Proved $ WitAll $ \case {}
      x `SCons` xs -> case f IZ x of
        Proved p -> case idecideAll @[] @_ @p (f . IS) xs of
          Proved a -> Proved $ WitAll $ \case
            IZ   -> p
            IS i -> runWitAll a i
          Disproved v -> Disproved $ \a -> v $ WitAll (runWitAll a . IS)
        Disproved v -> Disproved $ \a -> v $ runWitAll a IZ

    igenAllA
        :: forall (p :: k ~> Type) (as :: [k]) h. Applicative h
        => (forall a. Elem [] as a -> Sing a -> h (p @@ a))
        -> Sing as
        -> h (All [] p @@ as)
    igenAllA f = \case
        SNil         -> pure $ WitAll $ \case {}
        x `SCons` xs -> go <$> f IZ x <*> igenAllA (f . IS) xs
      where
        go :: p @@ b -> All [] p @@ bs -> All [] p @@ (b ': bs)
        go p a = WitAll $ \case
          IZ   -> p
          IS i -> runWitAll a i

-- | Witness an item in a type-level 'Maybe' by proving the 'Maybe' is
-- 'Just'.
data IsJust :: Maybe k -> k -> Type where
    IsJust :: IsJust ('Just a) a

deriving instance Show (IsJust as a)
instance (SingI (as :: Maybe k), SDecide k) => Decide (TyPred (IsJust as)) where
    decide x = withSingI x $ pickElem

type instance Elem Maybe = IsJust

instance Universe Maybe where
    idecideAny f = \case
      SNothing -> Disproved $ \case WitAny i _ -> case i of {}
      SJust x  -> case f IsJust x of
        Proved p    -> Proved $ WitAny IsJust p
        Disproved v -> Disproved $ \case
          WitAny IsJust p -> v p

    idecideAll f = \case
      SNothing -> Proved $ WitAll $ \case {}
      SJust x  -> case f IsJust x of
        Proved p    -> Proved $ WitAll $ \case IsJust -> p
        Disproved v -> Disproved $ \a -> v $ runWitAll a IsJust

    igenAllA f = \case
      SNothing -> pure $ WitAll $ \case {}
      SJust x  -> (\p -> WitAll $ \case IsJust -> p) <$> f IsJust x

-- | Witness an item in a type-level @'Either' j@ by proving the 'Either'
-- is 'Right'.
data IsRight :: Either j k -> k -> Type where
    IsRight :: IsRight ('Right a) a

deriving instance Show (IsRight as a)
instance (SingI (as :: Either j k), SDecide k) => Decide (TyPred (IsRight as)) where
    decide x = withSingI x $ pickElem

type instance Elem (Either j) = IsRight

instance Universe (Either j) where
    idecideAny f = \case
      SLeft  _ -> Disproved $ \case WitAny i _ -> case i of {}
      SRight x -> case f IsRight x of
        Proved p    -> Proved $ WitAny IsRight p
        Disproved v -> Disproved $ \case
          WitAny IsRight p -> v p

    idecideAll f = \case
      SLeft  _ -> Proved $ WitAll $ \case {}
      SRight x -> case f IsRight x of
        Proved p    -> Proved $ WitAll $ \case IsRight -> p
        Disproved v -> Disproved $ \a -> v $ runWitAll a IsRight

    igenAllA f = \case
      SLeft  _ -> pure $ WitAll $ \case {}
      SRight x -> (\p -> WitAll $ \case IsRight -> p) <$> f IsRight x

-- | Witness an item in a type-level 'NonEmpty' by either indicating that
-- it is the "head", or by providing an index in the "tail".
data NEIndex :: NonEmpty k -> k -> Type where
    NEHead :: NEIndex (a ':| as) a
    NETail :: Index as a -> NEIndex (b ':| as) a

deriving instance Show (NEIndex as a)
instance (SingI (as :: NonEmpty k), SDecide k) => Decide (TyPred (NEIndex as)) where
    decide x = withSingI x $ pickElem

type instance Elem NonEmpty = NEIndex

instance Universe NonEmpty where
    idecideAny
        :: forall k (p :: k ~> Type) (as :: NonEmpty k). ()
        => (forall a. Elem NonEmpty as a -> Sing a -> Decision (p @@ a))
        -> Sing as
        -> Decision (Any NonEmpty p @@ as)
    idecideAny f (x NE.:%| xs) = case f NEHead x of
      Proved p    -> Proved $ WitAny NEHead p
      Disproved v -> case idecideAny @[] @_ @p (f . NETail) xs of
        Proved (WitAny i p) -> Proved $ WitAny (NETail i) p
        Disproved vs     -> Disproved $ \case
          WitAny i p -> case i of
            NEHead    -> v p
            NETail i' -> vs (WitAny i' p)

    idecideAll
        :: forall k (p :: k ~> Type) (as :: NonEmpty k). ()
        => (forall a. Elem NonEmpty as a -> Sing a -> Decision (p @@ a))
        -> Sing as
        -> Decision (All NonEmpty p @@ as)
    idecideAll f (x NE.:%| xs) = case f NEHead x of
      Proved p -> case idecideAll @[] @_ @p (f . NETail) xs of
        Proved ps -> Proved $ WitAll $ \case
          NEHead   -> p
          NETail i -> runWitAll ps i
        Disproved v -> Disproved $ \a -> v $ WitAll (runWitAll a . NETail)
      Disproved v -> Disproved $ \a -> v $ runWitAll a NEHead

    igenAllA
        :: forall (p :: k ~> Type) (as :: NonEmpty k) h. Applicative h
        => (forall a. Elem NonEmpty as a -> Sing a -> h (p @@ a))
        -> Sing as
        -> h (All NonEmpty p @@ as)
    igenAllA f (x NE.:%| xs) = go <$> f NEHead x <*> igenAllA @[] @_ @p (f . NETail) xs
      where
        go :: p @@ b -> All [] p @@ bs -> All NonEmpty p @@ (b ':| bs)
        go p ps = WitAll $ \case
          NEHead   -> p
          NETail i -> runWitAll ps i

-- | Trivially witness an item in the second field of a type-level tuple.
data Snd :: (j, k) -> k -> Type where
    Snd :: Snd '(a, b) b

deriving instance Show (Snd as a)
instance (SingI (as :: (j, k)), SDecide k) => Decide (TyPred (Snd as)) where
    decide x = withSingI x $ pickElem

type instance Elem ((,) j) = Snd

instance Universe ((,) j) where
    idecideAny f (STuple2 _ x) = case f Snd x of
      Proved p    -> Proved $ WitAny Snd p
      Disproved v -> Disproved $ \case WitAny Snd p -> v p

    idecideAll f (STuple2 _ x) = case f Snd x of
      Proved p    -> Proved $ WitAll $ \case Snd -> p
      Disproved v -> Disproved $ \a -> v $ runWitAll a Snd

    igenAllA f (STuple2 _ x) = (\p -> WitAll $ \case Snd -> p) <$> f Snd x