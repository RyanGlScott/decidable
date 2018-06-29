{-# LANGUAGE AllowAmbiguousTypes   #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE GADTs                 #-}
{-# LANGUAGE LambdaCase            #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE RankNTypes            #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TypeApplications      #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE TypeInType            #-}
{-# LANGUAGE TypeOperators         #-}
{-# LANGUAGE TypeSynonymInstances  #-}
{-# LANGUAGE UndecidableInstances  #-}

module Data.Type.Quantification (
    Any, WitAny(..)
  , entailAny, ientailAny, entailAnyF, ientailAnyF
  , All, WitAll(..)
  , entailAll, ientailAll, entailAllF, ientailAllF, decideEntailAll, idecideEntailAll
  , Subset, WitSubset(..)
  , makeSubset, subsetToList, subsetToAny, subsetToAll
  , intersection, union, symDiff, mergeSubset, imergeSubset
  ) where

import           Control.Applicative
import           Data.Kind
import           Data.Monoid            (Alt(..))
import           Data.Singletons
import           Data.Singletons.Decide
import           Data.Type.Predicate
import           Data.Type.Universe

-- | A @'Subset' p as@ describes a /decidable/ subset of type-level
-- collection @as@.
newtype WitSubset f p (as :: f k) = WitSubset
    { runWitSubset :: forall a. Elem f as a -> Decision (p @@ a)
    }

data Subset f :: (k ~> Type) -> (f k ~> Type)
type instance Apply (Subset f p) as = WitSubset f p as

instance (Universe f, Decide p) => Decide (Subset f p)
instance (Universe f, Decide p) => Taken (Subset f p) where
    taken = makeSubset @f @_ @p (\_ -> decide @p)

-- | Create a 'Subset' from a predicate.
makeSubset
    :: forall f k p (as :: f k). Universe f
    => (forall a. Elem f as a -> Sing a -> Decision (p @@ a))
    -> Sing as
    -> Subset f p @@ as
makeSubset f xs = WitSubset $ \i -> f i (select i xs)

-- | Turn a 'Subset' into a list (or any 'Alternative') of satisfied
-- predicates.
subsetToList
    :: forall f p t. (Universe f, Alternative t)
    => (Subset f p --># Any f p) t
subsetToList xs s = getAlt $ (`ifoldMapUni` xs) $ \i _ -> Alt $ case runWitSubset s i of
    Proved p    -> pure $ WitAny i p
    Disproved _ -> empty

-- | Restrict a 'Subset' to a single (arbitrary) member, or fail if none
-- exists.
subsetToAny
    :: forall f p. Universe f
    => Subset f p -?> Any f p
subsetToAny xs s = idecideAny (\i _ -> runWitSubset s i) xs

-- | Combine two subsets based on a decision function
imergeSubset
    :: forall f k p q r (as :: f k). ()
    => (forall a. Elem f as a -> Decision (p @@ a) -> Decision (q @@ a) -> Decision (r @@ a))
    -> Subset f p @@ as
    -> Subset f q @@ as
    -> Subset f r @@ as
imergeSubset f ps qs = WitSubset $ \i ->
    f i (runWitSubset ps i) (runWitSubset qs i)

-- | Combine two subsets based on a decision function
mergeSubset
    :: forall f k p q r (as :: f k). ()
    => (forall a. Decision (p @@ a) -> Decision (q @@ a) -> Decision (r @@ a))
    -> Subset f p @@ as
    -> Subset f q @@ as
    -> Subset f r @@ as
mergeSubset f = imergeSubset (\(_ :: Elem f as a) p -> f @a p)

-- | Subset intersection
intersection
    :: forall f p q. ()
    => ((Subset f p &&& Subset f q) --> Subset f (p &&& q))
intersection _ = uncurry $ imergeSubset $ \(_ :: Elem f as a) -> proveAnd @p @q @a

-- | Subset union
union
    :: forall f p q. ()
    => ((Subset f p &&& Subset f q) --> Subset f (p ||| q))
union _ = uncurry $ imergeSubset $ \(_ :: Elem f as a) -> proveOr @p @q @a

symDiff
    :: forall f p q. ()
    => ((Subset f p &&& Subset f q) --> Subset f (p ^^^ q))
symDiff _ = uncurry $ imergeSubset $ \(_ :: Elem f as a) -> proveXor @p @q @a

-- | Test if a subset is equal to the entire original collection
subsetToAll
    :: forall f p. Universe f
    => Subset f p -?> All f p
subsetToAll xs s = idecideAll (\i _ -> runWitSubset s i) xs

-- | If there exists an @a@ s.t. @p a@, and if @p@ implies @q@, then there
-- must exist an @a@ s.t. @q a@.
ientailAny
    :: forall f p q as. (Universe f, SingI as)
    => (forall a. Elem f as a -> Sing a -> p @@ a -> q @@ a)        -- ^ implication
    -> Any f p @@ as
    -> Any f q @@ as
ientailAny f (WitAny i x) = WitAny i (f i (select i sing) x)

entailAny
    :: forall f p q. Universe f
    => (p --> q)
    -> (Any f p --> Any f q)
entailAny = tmap @(Any f)

-- | If for all @a@ we have @p a@, and if @p@ implies @q@, then for all @a@
-- we must also have @p a@.
ientailAll
    :: forall f p q as. (Universe f, SingI as)
    => (forall a. Elem f as a -> Sing a -> p @@ a -> q @@ a)      -- ^ implication
    -> All f p @@ as
    -> All f q @@ as
ientailAll f a = WitAll $ \i -> f i (select i sing) (runWitAll a i)

entailAll
    :: forall f p q. Universe f
    => (p --> q)
    -> (All f p --> All f q)
entailAll = tmap @(All f)

-- | If @p@ implies @q@ under some context @h@, and if there exists some
-- @a@ such that @p a@, then there must exist some @a@ such that @p q@
-- under that context @h@.
--
-- @h@ might be something like, say, 'Maybe', to give predicate that is
-- either provably true or unprovably false.
--
-- Note that it is not possible to do this with @p a -> 'Decision' (q a)@.
-- This is if the @p a -> 'Decision' (q a)@ implication is false, there
-- it doesn't mean that there is /no/ @a@ such that @q a@, necessarily.
-- There could have been an @a@ where @p@ does not hold, but @q@ does.
ientailAnyF
    :: forall f p q as h. Functor h
    => (forall a. Elem f as a -> p @@ a -> h (q @@ a))      -- ^ implication in context
    -> Any f p @@ as
    -> h (Any f q @@ as)
ientailAnyF f = \case WitAny i x -> WitAny i <$> f i x

-- | 'entailAnyF', but without the membership witness.
entailAnyF
    :: forall f p q h. (Universe f, Functor h)
    => (p --># q) h                                     -- ^ implication in context
    -> (Any f p --># Any f q) h
entailAnyF f x a = withSingI x $
    ientailAnyF @f @p @q (\i -> f (select i x)) a

-- | If @p@ implies @q@ under some context @h@, and if we have @p a@ for
-- all @a@, then we must have @q a@ for all @a@ under context @h@.
ientailAllF
    :: forall f p q as h. (Universe f, Applicative h, SingI as)
    => (forall a. Elem f as a -> p @@ a -> h (q @@ a))    -- ^ implication in context
    -> All f p @@ as
    -> h (All f q @@ as)
ientailAllF f a = igenAllA (\i _ -> f i (runWitAll a i)) sing

-- | 'entailAllF', but without the membership witness.
entailAllF
    :: forall f p q h. (Universe f, Applicative h)
    => (p --># q) h                                     -- ^ implication in context
    -> (All f p --># All f q) h
entailAllF f x a = withSingI x $
    ientailAllF @f @p @q (\i -> f (select i x)) a

-- | If we have @p a@ for all @a@, and @p a@ can be used to test for @q a@,
-- then we can test all @a@s for @q a@.
idecideEntailAll
    :: forall f p q as. (Universe f, SingI as)
    => (forall a. Elem f as a -> p @@ a -> Decision (q @@ a))     -- ^ decidable implication
    -> All f p @@ as
    -> Decision (All f q @@ as)
idecideEntailAll f a = idecideAll (\i _ -> f i (runWitAll a i)) sing

-- | 'decideEntailAll', but without the membeship witness.
decideEntailAll
    :: forall f p q. Universe f
    => p -?> q
    -> All f p -?> All f q
decideEntailAll = dmap @(All f)