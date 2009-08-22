{-# LANGUAGE ScopedTypeVariables #-}

import Control.Arrow ((&&&), second, first)
import Control.Monad (filterM, guard)
import Control.Monad.State.Strict (State, get, put, evalState)
import Data.Char (intToDigit, isLatin1, isPrint)
import Data.Function (fix)
import Data.List (genericLength, find, group, minimumBy, sort)
import Data.Maybe (isJust, fromJust)
import Data.Number.Natural (Natural)
import Data.Ord (comparing)
import System.Environment (getArgs)
import System.IO.Unsafe (unsafePerformIO)
import System.Process (readProcess)

import qualified Data.Map as M
import Data.Map (Map)

type Fungifier i = i -> State (Map i String) String

runFungifier :: Fungifier i -> i -> String
runFungifier f n = evalState (f n) M.empty

fungified :: Integral i => i -> String -> State (Map i String) String
fungified n s = do
   m <- get
   case M.lookup n m of
        Just s' -> return s'
        Nothing -> do
           put $ M.insert n s m
           return s

main :: IO ()
main = (getArgs >>=) . mapM_ $ \s -> do
   let n = read s :: Integer
   putStrLn $ runFungifier fungifyNeg n

fungifyNeg, fungify, naiveFungify, easyFungify :: Integral i => Fungifier i
fungifyNeg n | n >= 0    = fungify n
             | otherwise = do
                f <- fungify (-n)
                fungified n $ concat ["0", f, "-"]

fungify n | isEasy n  = easyFungify n
          | otherwise = do
             options <- mapM fungFacs . factorizations $ n
             let best = fst . minimumBy (comparing snd) $ options
             fungified n best
 where
  fungFacs factorization = do
     facs <- mapM fungFac factorization
     let s    = concat facs
         lf   = length facs
     return (s ++ replicate (lf - 1) '*', length s + lf - 1)

  fungFac x@(factor,p)
     | isEasy (factor^p) = easyFungify (factor^p)
     | otherwise         =
        let y@(m,p') = splitMul x
         in if y == x
               then naiveFungifyWith fungify (m^p)
               else do
                  fm <- fungify m
                  ff <- fungify (factor ^ p')
                  fungified n $ concat [fm, ff, "*"]

splitMul :: Integral i => (i,i) -> (i,i)
splitMul x@(factor,_) =
  safeLast' x (second pred) $ whileL (\(n,p) -> n <= 15 && p > 1)
                                     (\(n,p) -> (factor*n, p-1))
                                     x

naiveFungify = fix naiveFungifyWith

naiveFungifyWith :: Integral i => Fungifier i -> Fungifier i
naiveFungifyWith f n
   | isEasy n  = easyFungify n
   | otherwise = do
      let s = case fromJust.fromJust . find isJust $
                       [ findSum isTrivial nzEasies
                       , findSum isEasy    nzEasies
                       , Just (Left maxPrintable)
                       ] of
                    Left  e -> [f (n-e), f e, return "+"]
                    Right e -> [f (n+e), f e, return "-"]

      ms <- sequence s
      fungified n $ concat ms
 where
   findSum p (e:es) | p (n+e)   = Just $ Right e
                    | p (n-e)   = Just $ Left e
                    | otherwise = findSum p es
   findSum _ [] = Nothing

easyFungify n
   | n < 16                  = fungified n [intToDigit $ fromIntegral n]
   | isLatin1 c && isPrint c = fungified n ['\'', c]
   | otherwise               = error$ "easyFungify :: not easy: " ++ show n
 where
   c = toEnum . fromIntegral $ n

isEasy, isTrivial :: Integral i => i -> Bool
isTrivial n = n >= 0 &&  n < 16
isEasy    n = n >= 0 && (n < 16 || (n <= m && isLatin1 c && isPrint c))
 where
   m = fromIntegral $ fromEnum (maxBound :: Char)
   c = toEnum . fromIntegral $ n

maxPrintable :: Integral i => i
maxPrintable = last printables

printables, nzEasies :: Integral i => [i]
printables = filter (isPrint.toEnum.fromIntegral) [0..255]

nzEasies = [1..15] ++ printables

safeLast' :: b -> (a -> b) -> [a] -> b
safeLast' x _ [] = x
safeLast' _ f xs = f (last xs)

whileL :: (a -> Bool) -> (a -> a) -> a -> [a]
whileL p f = takeWhile p . iterate f

factorizations :: (Integral i, Integral p) => i -> [[(i,p)]]
factorizations = map lengthGroup . plainFactorizations

plainFactors :: Integral i => i -> [i]
plainFactors 0         = [0]
plainFactors n | n < 0 = -1 : plainFactors (-n)
plainFactors n         = unsafePerformIO $ do
   fs <- readProcess "factor" [show n] ""
   return (map (fromIntegral.(read :: String->Integer)) . tail . words $ fs)

factors :: (Integral i, Integral p) => i -> [(i,p)]
factors = lengthGroup . plainFactors

lengthGroup :: (Eq a, Integral l) => [a] -> [(a,l)]
lengthGroup = map (head &&& genericLength) . group

lazyLength :: [a] -> Natural
lazyLength = genericLength

-- All the rest is thanks to Brent Yorgey's article in The.Monad.Reader issue
-- 8, "Generating Multiset Partitions"
type Vec = [Int]
data MultiSet a = MS [a] Vec deriving Show

plainFactorizations :: Integral i => i -> [[i]]
plainFactorizations = (map.map) product . partitions . plainFactors
 where
   partitions = map (map msToList) . mPartitions . msFromList

   msFromList = uncurry MS . unzip . lengthGroup . sort

   msToList (MS es cs) = concat $ zipWith replicate cs es

   mPartitions (MS elts v) = map (map (MS elts)) $ vPartitions v

   vPartitions v = vPart v (vUnit v)

   vPart v  _ | all (==0) v = [[]]
   vPart v vL =
      [v] : [v':p | v' <- withinFromTo v (vHalf v) vL
                  , p  <- vPart (zipWith (-) v v') v']

   vUnit [] = []
   vUnit [_] = [1]
   vUnit (_:xs) = 0 : vUnit xs

   vHalf :: Vec -> Vec
   vHalf [] = []
   vHalf (x:xs) | (even x)  = (x `quot` 2) : vHalf xs
                | otherwise = (x `quot` 2) : xs

   withinFromTo m s e | s >| m    = withinFromTo m (zipWith min m s) e
                      | e >  s    = []
                      | otherwise = wFT m s e True True
    where
      wFT [] _ _ _ _ = [[]]
      wFT (m:ms) (s:ss) (e:es) useS useE =
         let start = if useS then s else m
             end = if useE then e else 0
          in [x:xs | x  <- [start,(start-1)..end]
                   , xs <- wFT ms ss es (useS && x==s) (useE && x==e)]

      xs >| ys = and $ zipWith (>) xs ys
