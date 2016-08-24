{-#LANGUAGE FlexibleContexts , TemplateHaskell#-}

module Eval.Primitive.PrimiType where

import Data.DataType
import Data.Number.Number
import Data.Environment.Environment

import qualified Data.Map.Strict as M
import Control.Monad
import Control.Monad.Except
import Control.Monad.Trans.State
import Control.Lens hiding(List, Context)
import Data.Maybe
import qualified Data.Text as T


-- * Types and common functions for defining primitive functions.

type Result = ThrowsError (Maybe LispVal)
type IOResult = IOThrowsError (Maybe LispVal)

type EvalResult = IOThrowsError LispVal

type StateResult a = StateT PrimiEnv IOThrowsError a

-- | Basic primitive function which only perform simple term rewriting
type Primi = StateResult LispVal

type Eval = LispVal -> Primi

type Primitives = M.Map T.Text Primi

type EvalArguments = [LispVal] -> IOThrowsError LispVal


-- | Envrionment for primitive function
data PrimiEnv = PrimiEnv
  { _eval :: Eval
  , _con :: Context
  , _args :: [LispVal]
  -- , _modified :: Bool
  , _dep :: Int
  , _line :: Int
  }

makeLenses ''PrimiEnv



stateThrow :: LispError -> StateResult a
stateThrow = lift . throwError
-- | The most genenral function to constraint the arguments number of
-- primitive function
checkArgsNumber :: (Int -> Bool) -> (LispVal -> Int -> IOThrowsError ()) ->
  StateResult ()
checkArgsNumber check throw = do
  num <- uses args ((\x -> x - 1) . length)
  unless (check num) $ do
    name <- uses args head
    lift (throw name num)

-- | expects more than n arguments.
manynop n = checkArgsNumber (>= n) throw
  where throw val x = throwError (NumArgsMore (unpackAtom val) n x)

-- | expect more than one arugments
many1op = manynop 1

-- | argument list length is between l and r.
between l r = checkArgsNumber (\x -> x >= l && x <= r) throw
  where throw val x = throwError (NumArgsBetween (unpackAtom val) l r x)

-- | Ensure that the argument list has excatly n elements.
withnop n = checkArgsNumber (== n) throw
  where throw val x = throwError (NumArgs (unpackAtom val) n x)

-- | evaluate a LispVal with function in PrimiEnv context
evaluate :: LispVal -> Primi
evaluate val = do
  evalFun <- getEval
  evalFun val

-- | get evaluate function
getEval :: StateResult Eval
getEval = use eval

--  | get context
getCon :: StateResult Context
getCon = use con

getLineNumber :: StateResult Int
getLineNumber = use line

-- | update context
updateCon :: (Context -> Context) -> StateResult ()
updateCon f = con %= f

setVariable :: LispVal -> LispVal -> StateResult ()
setVariable lhs rhs = updateCon (updateContext lhs rhs)

getVariable :: LispVal -> Primi
getVariable lhs = uses con (replaceContext lhs)

-- | return args
getArgs :: StateResult [LispVal]
getArgs = use args

-- | return the arguments that is currently being evaluated
getArgumentList :: StateResult [LispVal]
getArgumentList = uses args tail

-- | apply function to argument list
usesArgumentList :: ([LispVal] -> a) -> StateResult a
usesArgumentList f = uses args (f . tail)

-- | return original expression if evaluate to nothing
usesArgumentMaybe :: ([LispVal] -> Maybe LispVal) -> StateResult LispVal
usesArgumentMaybe f = do
  expr <- getExpression
  usesArgumentList (fromMaybe expr . f)

-- | lift a IOThrowsError to StateResult
usesArgumentError :: EvalArguments -> StateResult LispVal
usesArgumentError f = do
  argument <- getArgumentList
  lift (f argument)

-- | return head
getHead :: Primi
getHead = uses args head

-- | return whole expression to be evaluated
getExpression :: Primi
getExpression = uses args List

-- | tag list with same head in the environment
tagHead :: [LispVal] -> Primi
tagHead args = do
  h <- getHead
  return (List (h:args))

-- | return without evaluation
noChange :: Primi
noChange = uses args List
