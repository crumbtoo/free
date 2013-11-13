{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE UndecidableInstances #-}
module Control.Monad.Trans.Free.Church
  (
  -- * The free monad transformer
    FT(..)
  -- * The free monad
  , F, free, runF
  -- * Operations
  , foo, bar
  , iterT
  , hoistFT
  , transFT
  -- * Operations of free monad
  , retract
  , iter
  , iterM
  -- * Free Monads With Class
  , MonadFree(..)
  ) where

import Control.Applicative
import Control.Monad
import Control.Monad.Identity
import Control.Monad.Trans.Class
import Control.Monad.IO.Class
import Control.Monad.Reader.Class
import Control.Monad.State.Class
import Control.Monad.Free.Class
import Control.Monad.Trans.Free (FreeT(..), FreeF(..))
import Data.Foldable (Foldable)
import qualified Data.Foldable as F
import Data.Monoid
import Data.Functor.Bind hiding (join)

newtype FT f m a = FT {runFT :: forall r. (a -> m r) -> (f (m r) -> m r) -> m r}

instance Functor (FT f m) where
  fmap f (FT k) = FT $ \a fr -> k (a . f) fr

instance Apply (FT f m) where
  (<.>) = (<*>)

instance Applicative (FT f m) where
  pure a = FT $ \k _ -> k a
  FT fk <*> FT ak = FT $ \b fr -> ak (\d -> fk (\e -> b (e d)) fr) fr

instance Bind (FT f m) where
  (>>-) = (>>=)

instance Monad (FT f m) where
  return = pure
  FT fk >>= f = FT $ \b fr -> fk (\d -> runFT (f d) b fr) fr

instance (Functor f) => MonadFree f (FT f m) where
  wrap f = FT (\kp kf -> kf (fmap (\(FT m) -> m kp kf) f))

instance MonadTrans (FT f) where
  lift m = FT (\a _ -> m >>= a)

instance Alternative m => Alternative (FT f m) where
  empty = FT (\_ _ -> empty)
  FT k1 <|> FT k2 = FT $ \a fr -> k1 a fr <|> k2 a fr

instance MonadPlus m => MonadPlus (FT f m) where
  mzero = FT (\_ _ -> mzero)
  mplus (FT k1) (FT k2) = FT $ \a fr -> k1 a fr `mplus` k2 a fr

instance (Foldable f, Foldable m, Monad m) => Foldable (FT f m) where
  foldMap f (FT k) = F.fold $ k (return . f) (F.foldr (liftM2 mappend) (return mempty))

instance (MonadIO m) => MonadIO (FT f m) where
  liftIO = lift . liftIO
  {-# INLINE liftIO #-}

instance (Functor f, MonadReader r m) => MonadReader r (FT f m) where
  ask = lift ask
  {-# INLINE ask #-}
  local f = hoistFT (local f)
  {-# INLINE local #-}

instance (Functor f, MonadState s m) => MonadState s (FT f m) where
  get = lift get
  {-# INLINE get #-}
  put = lift . put
  {-# INLINE put #-}
#if MIN_VERSION_mtl(2,1,1)
  state f = lift (state f)
  {-# INLINE state #-}
#endif

foo :: (Monad m, Functor f) => FreeT f m a -> FT f m a
foo (FreeT f) = FT $ \ka kfr -> do
  freef <- f
  case freef of
    Pure a -> ka a
    Free fb -> kfr $ fmap (($ kfr) . ($ ka) . runFT . foo) fb

bar :: (Monad m, Functor f) => FT f m a -> FreeT f m a
bar (FT k) = FreeT $ k (return . Pure) (runFreeT . wrap . fmap FreeT)

-- | The \"free monad\" for a functor @f@.
type F f = FT f Identity

runF :: Functor f => F f a -> (forall r. (a -> r) -> (f r -> r) -> r)
runF (FT m) = \kp kf -> runIdentity $ m (return . kp) (return . kf . fmap runIdentity)

free :: Functor f => (forall r. (a -> r) -> (f r -> r) -> r) -> F f a
free f = FT (\kp kf -> return $ f (runIdentity . kp) (runIdentity . kf . fmap return))

-- | Tear down a free monad transformer using iteration.
iterT :: (Functor f, Monad m) => (f (m a) -> m a) -> FT f m a -> m a
iterT phi (FT m) = m return phi

-- | Lift a monad homomorphism from @m@ to @n@ into a monad homomorphism from @'FT' f m@ to @'FT' f n@
--
-- @'hoistFT' :: ('Monad' m, 'Monad' n, 'Functor' f) => (m ~> n) -> 'FT' f m ~> 'FT' f n@
hoistFT :: (Monad m, Monad n, Functor f) => (forall a. m a -> n a) -> FT f m b -> FT f n b
hoistFT phi (FT m) = FT (\kp kf -> join . phi $ m (return . kp) (return . kf . fmap (join . phi)))

-- | Lift a natural transformation from @f@ to @g@ into a monad homomorphism from @'FT' f m@ to @'FT' g n@
transFT :: (Monad m, Functor g) => (forall a. f a -> g a) -> FT f m b -> FT g m b
transFT phi (FT m) = FT (\kp kf -> m kp (kf . phi))

-- |
-- 'retract' is the left inverse of 'liftF'
--
-- @
-- 'retract' . 'liftF' = 'id'
-- @
retract :: Monad f => F f a -> f a
retract (FT m) = runIdentity $ m (return . return) (return . join . liftM runIdentity)

-- | Tear down an 'F' 'Monad' using iteration.
iter :: Functor f => (f a -> a) -> F f a -> a
iter phi = runIdentity . iterT (Identity . phi . fmap runIdentity)

-- | Like 'iter' for monadic values.
iterM :: (Functor f, Monad m) => (f (m a) -> m a) -> F f a -> m a
iterM phi = iterT phi . hoistFT (return . runIdentity)

