{-# LANGUAGE AllowAmbiguousTypes   #-}
{-# LANGUAGE ConstraintKinds       #-}
{-# LANGUAGE EmptyCase             #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE KindSignatures        #-}
{-# LANGUAGE LambdaCase            #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TypeApplications      #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE TypeInType            #-}
{-# LANGUAGE TypeOperators         #-}
{-# LANGUAGE UndecidableInstances  #-}

-- |
-- Module      : Data.Type.Predicate.Auto
-- Copyright   : (c) Justin Le 2018
-- License     : BSD3
--
-- Maintainer  : justin@jle.im
-- Stability   : experimental
-- Portability : non-portable
--
-- Useful utilities for situations where you know that a predicate @P@ is
-- satisfied for a specific @a@ at compile-time.
--
-- @since 0.1.1.0
module Data.Type.Predicate.Auto (
  -- * Automatically generate witnesses at compile-time
    Auto(..)
  , AutoNot, autoNot
  , AutoProvable
  -- ** Helper classes
  , AutoElem(..)
  , AutoAll(..)
  -- * Auto with help
  , autoAny, autoNotAll
  ) where

import           Data.Functor.Identity
import           Data.Kind
import           Data.List.NonEmpty                 (NonEmpty(..))
import           Data.Singletons
import           Data.Singletons.Sigma
import           Data.Type.Equality
import           Data.Type.Predicate
import           Data.Type.Predicate.Logic
import           Data.Type.Predicate.Param
import           Data.Type.Predicate.Quantification
import           Data.Type.Universe

-- | Automatically generate a witness for predicate @p@ applied to input
-- @a@.
--
-- Mostly useful for situations where you know @a@ at compile-time, so you
-- can just write 'auto' directly in your source code.  The choice is
-- intended to mirror the @auto@ keyword in languages like Idris.
--
-- Very close in nature to the @Known@ typeclass in the /type-combinators/
-- library.
--
-- Admittedly this interface is a bit clunky and ad-hoc; at this point you
-- can just try writing 'auto' in your code and praying that it works.  You
-- always have the option, of course, to just manually write proofs.  If
-- you have any inference rules to suggest, feel free to submit a PR!
--
-- An important limitation of 'Auto' is the Haskell type system prevents
-- "either-or" constraints; this could potentially be implemented using
-- compiler plugins.
--
-- One consequence of this is that it is impossible to automatically derive
-- @'Any' f p@ and @'Not' ('All' f p)@.
--
-- For these, the compiler needs help; you can use 'autoAny' and
-- 'autoNotAll' for these situations.
class Auto (p :: Predicate k) (a :: k) where
    -- | Have the compiler generate a witness for @p \@\@ a@.
    --
    -- Must be called using type application syntax:
    --
    -- @
    -- 'auto' @_ @p @a
    -- @
    auto :: p @@ a

instance SingI a => Auto Evident a where
    auto = WrapSing sing

-- | @since 0.1.2.0
instance SingI a => Auto (Not Impossible) a where
    auto = ($ WrapSing sing)

instance Auto (EqualTo a) a where
    auto = Refl

instance (Auto p a, Auto q a) => Auto (p &&& q) a where
    auto = (auto @_ @p @a, auto @_ @q @a)

instance Auto q a => Auto (p ==> q) a where
    auto _ = auto @_ @q @a

-- | Helper "predicate transformer" that gives you an instant 'auto' for
-- any 'Provable' instance.
--
-- For example, say you have predicate @P@ that you know is 'Provable', and
-- you wish to generate a @P \@\@ x@, for some specific @x@ you know at
-- compile-time.  You can use:
--
-- @
-- 'auto' \@_ \@('AutoProvable' P) \@x
-- @
--
-- to obtain a @P \@\@ x@.
--
-- 'AutoProvable' is essentially the identity function.
data AutoProvable :: Predicate k -> Predicate k
type instance Apply (AutoProvable p) a = p @@ a

instance (Provable p, SingI a) => Auto (AutoProvable p) a where
    auto = prove @p @a sing

-- | Typeclass representing 'Elem's pointing to an @a :: k@ that can be
-- generated automatically from type-level collection @as :: f k@.
--
-- If GHC knows both the type-level collection and the element you want to
-- find at compile-time, this instance should allow it to find it.
--
-- Used to help in the instance of 'Auto' for the 'In' predicate.
--
-- Example usage:
--
-- @
-- 'autoElem' :: 'Index' '[1,6,2,3] 2
-- -- IS (IS IZ)        -- third spot
-- @
--
-- And when used with 'Auto':
--
-- @
-- 'auto' \@_ \@('In' [] '[1,6,2,3]) \@2
-- -- IS (IS IZ)
-- @
class AutoElem f (as :: f k) (a :: k) where
    -- | Generate the 'Elem' pointing to the @a :: @ in a type-level
    -- collection @as :: f k@.
    autoElem :: Elem f as a

instance {-# OVERLAPPING #-} AutoElem [] (a ': as) a where
    autoElem = IZ

instance {-# OVERLAPPING #-} AutoElem [] as a => AutoElem [] (b ': as) a where
    autoElem = IS autoElem

instance AutoElem Maybe ('Just a) a where
    autoElem = IJust

instance AutoElem (Either j) ('Right a) a where
    autoElem = IRight

instance AutoElem NonEmpty (a ':| as) a where
    autoElem = NEHead

instance AutoElem [] as a => AutoElem NonEmpty (b ':| as) a where
    autoElem = NETail autoElem

-- | @since 0.1.2.0
instance AutoElem ((,) j) '(w, a) a where
    autoElem = ISnd

-- TODO: ???
-- instance AutoElem (f :.: g) p ('Comp ass) where

instance AutoElem Identity ('Identity a) a where
    autoElem = IId

instance AutoElem f as a => AutoElem (f :+: g) ('InL as) a where
    autoElem = IInL autoElem

instance AutoElem g bs b => AutoElem (f :+: g) ('InR bs) b where
    autoElem = IInR autoElem

instance AutoElem f as a => Auto (In f as) a where
    auto = autoElem @_ @f @as @a

-- | Helper class for deriving 'Auto' instances for 'All' predicates; each
-- 'Universe' instance is expected to implement these if possible, to get
-- free 'Auto' instaces for their 'All' predicates.
--
-- Also helps for 'Not' 'Any' predicates and 'Not' 'Found' 'AnyMatch'
-- predicates.
--
-- @since 0.1.2.0
class AutoAll (f :: Type -> Type) (p :: Predicate k) (as :: f k) where
    -- | Generate an 'All' for a given predicate over all items in @as@.
    autoAll :: All f p @@ as

instance AutoAll [] p '[] where
    autoAll = WitAll $ \case {}

instance (Auto p a, AutoAll [] p as) => AutoAll [] p (a ': as) where
    autoAll = WitAll $ \case
        IZ   -> auto @_ @p @a
        IS i -> runWitAll (autoAll @_ @[] @p @as) i

instance AutoAll Maybe p 'Nothing where
    autoAll = WitAll $ \case {}

instance Auto p a => AutoAll Maybe p ('Just a) where
    autoAll = WitAll $ \case IJust -> auto @_ @p @a

instance AutoAll (Either j) p ('Left e) where
    autoAll = WitAll $ \case {}

instance Auto p a => AutoAll (Either j) p ('Right a) where
    autoAll = WitAll $ \case IRight -> auto @_ @p @a

instance (Auto p a, AutoAll [] p as) => AutoAll NonEmpty p (a ':| as) where
    autoAll = WitAll $ \case
        NEHead   -> auto @_ @p @a
        NETail i -> runWitAll (autoAll @_ @[] @p @as) i

instance AutoAll f (All g p) ass => AutoAll (f :.: g) p ('Comp ass) where
    autoAll = WitAll $ \(i :? j) ->
      runWitAll (runWitAll (autoAll @_ @f @(All g p) @ass) i) j

instance Auto p a => AutoAll ((,) j) p '(w, a) where
    autoAll = WitAll $ \case ISnd -> auto @_ @p @a

instance AutoAll Proxy p 'Proxy where
    autoAll = WitAll $ \case {}

instance Auto p a => AutoAll Identity p ('Identity a) where
    autoAll = WitAll $ \case IId -> auto @_ @p @a

instance AutoAll f p as => AutoAll (f :+: g) p ('InL as) where
    autoAll = allSumL $ autoAll @_ @f @p @as

instance AutoAll g p bs => AutoAll (f :+: g) p ('InR bs) where
    autoAll = allSumR $ autoAll @_ @g @p @bs

-- | @since 0.1.2.0
instance AutoAll f p as => Auto (All f p) as where
    auto = autoAll @_ @f @p @as

-- | @since 0.1.2.0
instance SingI a => Auto (NotNull []) (a ': as) where
    auto = WitAny IZ $ WrapSing sing

-- | @since 0.1.2.0
instance SingI a => Auto IsJust ('Just a) where
    auto = WitAny IJust $ WrapSing sing

-- | @since 0.1.2.0
instance SingI a => Auto IsRight ('Right a) where
    auto = WitAny IRight $ WrapSing sing

-- | @since 0.1.2.0
instance SingI a => Auto (NotNull NonEmpty) (a ':| as) where
    auto = WitAny NEHead $ WrapSing sing

-- | @since 0.1.2.0
instance SingI a => Auto (NotNull ((,) j)) '(w, a) where
    auto = WitAny ISnd $ WrapSing sing

instance SingI a => Auto (NotNull Identity) ('Identity a) where
    auto = WitAny IId $ WrapSing sing

instance Auto (NotNull f) as => Auto (NotNull (f :+: g)) ('InL as) where
    auto = anySumL $ auto @_ @(NotNull f) @as

instance Auto (NotNull g) bs => Auto (NotNull (f :+: g)) ('InR bs) where
    auto = anySumR $ auto @_ @(NotNull g) @bs

-- | An @'AutoNot' p a@ constraint means that @p \@\@ a@ can be proven to
-- not be true at compiletime.
--
-- @since 0.1.2.0
type AutoNot (p :: Predicate k) = Auto (Not p)

-- | Disprove @p \@\@ a@ at compiletime.
--
-- @
-- 'autoNot' \@_ \@p \@a :: 'Not' p '@@' a
-- @
--
-- @since 0.1.2.0
autoNot :: forall k (p :: Predicate k) (a :: k). AutoNot p a => Not p @@ a
autoNot = auto @k @(Not p) @a

-- | @since 0.1.2.0
instance Auto (Found p) (f @@ a) => Auto (Found (PPMap f p)) a where
    auto = case auto @_ @(Found p) @(f @@ a) of
        i :&: p -> i :&: p

-- | @since 0.1.2.0
instance Auto (NotFound p) (f @@ a) => Auto (NotFound (PPMap f p)) a where
    auto = mapRefuted (\(i :&: p) -> i :&: p)
         $ autoNot @_ @(Found p) @(f @@ a)

-- | @since 0.1.2.0
instance Auto p (f @@ a) => Auto (PMap f p) a where
    auto = auto @_ @p @(f @@ a)

-- | @since 0.1.2.0
instance AutoNot p (f @@ a) => Auto (Not (PMap f p)) a where
    auto = autoNot @_ @p @(f @@ a)

-- | Helper function to generate an @'Any' f p@ if you can pick out
-- a specific @a@ in @as@ where the predicate is provable at compile-time.
--
-- This is used to get around a fundamental limitation of 'Auto' as
-- a Haskell typeclass.
--
-- @since 0.1.2.0
autoAny
    :: forall f p as a. Auto p a
    => Elem f as a
    -> Any f p @@ as
autoAny i = WitAny i (auto @_ @p @a)

-- | @since 0.1.2.0
instance (SingI as, AutoAll f (Not p) as) => Auto (Not (Any f p)) as where
    auto = allNotNone sing $ autoAll @_ @f @(Not p) @as

-- | Helper function to generate a @'Not' ('All' f p)@ if you can pick out
-- a specific @a@ in @as@ where the predicate is disprovable at compile-time.
--
-- This is used to get around a fundamental limitation of 'Auto' as
-- a Haskell typeclass.
--
-- @since 0.1.2.0
autoNotAll
    :: forall p f as a. (AutoNot p a, SingI as)
    => Elem f as a
    -> Not (All f p) @@ as
autoNotAll = anyNotNotAll sing . autoAny

-- | @since 0.1.2.0
instance (SingI as, AutoAll f (Not (Found p)) as) => Auto (Not (Found (AnyMatch f p))) as where
    auto = mapRefuted (\(s :&: WitAny i p) -> WitAny i (s :&: p))
         $ auto @_ @(Not (Any f (Found p))) @as
