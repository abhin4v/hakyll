-- | Internally used compiler module
--
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Hakyll.Core.Compiler.Internal
    ( Dependencies
    , CompilerEnvironment (..)
    , CompilerM (..)
    , Compiler (..)
    , runCompilerJob
    , runCompilerDependencies
    , fromJob
    , fromDependencies
    ) where

import Prelude hiding ((.), id)
import Control.Applicative (Applicative, (<$>))
import Control.Monad.Reader (ReaderT, Reader, ask, runReaderT, runReader)
import Control.Monad ((<=<), liftM2)
import Data.Set (Set)
import qualified Data.Set as S
import Control.Category (Category, (.), id)
import Control.Arrow (Arrow, arr, first)

import Hakyll.Core.Identifier
import Hakyll.Core.CompiledItem
import Hakyll.Core.ResourceProvider

-- | A set of dependencies
--
type Dependencies = Set Identifier

-- | A lookup with which we can get dependencies
--
type DependencyLookup = Identifier -> CompiledItem

-- | Environment in which a compiler runs
--
data CompilerEnvironment = CompilerEnvironment
    { compilerIdentifier       :: Identifier        -- ^ Target identifier
    , compilerResourceProvider :: ResourceProvider  -- ^ Resource provider
    , compilerDependencyLookup :: DependencyLookup  -- ^ Dependency lookup
    }

-- | The compiler monad
--
newtype CompilerM a = CompilerM
    { unCompilerM :: ReaderT CompilerEnvironment IO a
    } deriving (Monad, Functor, Applicative)

-- | The compiler arrow
--
data Compiler a b = Compiler
    { compilerDependencies :: Reader ResourceProvider Dependencies
    , compilerJob          :: a -> CompilerM b
    }

instance Category Compiler where
    id = Compiler (return S.empty) return
    (Compiler d1 j1) . (Compiler d2 j2) =
        Compiler (liftM2 S.union d1 d2) (j1 <=< j2)

instance Arrow Compiler where
    arr f = Compiler (return S.empty) (return . f)
    first (Compiler d j) = Compiler d $ \(x, y) -> do
        x' <- j x
        return (x', y)

-- | Run a compiler, yielding the resulting target and it's dependencies
--
runCompilerJob :: Compiler () a
               -> Identifier
               -> ResourceProvider
               -> DependencyLookup
               -> IO a
runCompilerJob compiler identifier provider lookup' =
    runReaderT (unCompilerM $ compilerJob compiler ()) env
  where
    env = CompilerEnvironment
            { compilerIdentifier       = identifier
            , compilerResourceProvider = provider
            , compilerDependencyLookup = lookup'
            }

runCompilerDependencies :: Compiler () a
                        -> ResourceProvider
                        -> Dependencies
runCompilerDependencies compiler provider =
    runReader (compilerDependencies compiler) provider

fromJob :: (a -> CompilerM b)
        -> Compiler a b
fromJob = Compiler (return S.empty)

fromDependencies :: (ResourceProvider -> [Identifier])
                 -> Compiler b b
fromDependencies deps = Compiler (S.fromList . deps <$> ask) return
