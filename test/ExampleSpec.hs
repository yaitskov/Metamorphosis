{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE StandaloneDeriving, FlexibleInstances, FlexibleContexts #-}
module ExampleSpec where

import Test.Hspec
import Lens.Micro
import Metamorphosis
import Control.Monad
import Metamorphosis.Applicative
import Data.Functor.Identity
import Control.Applicative
import Data.Maybe
import Data.Monoid (mempty, (<>))

-- * Simple record
data Product = Product { style :: String
                       , variation :: String
                       , price :: Double
                       , quantity :: Int
                       } deriving (Show, Eq)

-- | Generates Style type
-- data Style = Style { style :: String
--                    , price :: Double
--                    } deriving (Show, Eq)
$(metamorphosis
   ( (\fd -> if fd ^. fdFieldName `elem` map Just ["variation", "quantity"]
             then []
             else [fd])
   . (fdTConsName .~ "Style")
   )
   [''Product]
   (\n -> if n `elem` ["ProductToStyle", "Product'StyleToProduct"]
          then (Just identityBCR)
          else Nothing
   )
   (const [''Show, ''Eq])
 )

styleSpecs = 
  describe "Style" $ do
    it "gets a Style from a Product" $ do
      iProductToStyle (Product "style" "var" 15.5 2 ) `shouldBe` (Style "style" 15.50) 
    it "sets a Style inside a Product" $ do
      iProduct'StyleToProduct (Product "style" "var" 15.0 2) (Style "new" 7) `shouldBe` (Product "new" "var" 7.0 2)

-- * Record parametrized by a functor.
data Record = Record { code :: String, price :: Double} deriving (Read, Show, Eq, Ord)
-- | Generates parametric version of Record
-- Unfortunately we can't derives Eq and Show in the general case, so we'll have to
-- do it manually.
-- data RecordF f = RecordF f { code :: f String, price :: f Double}
$(metamorphosis
   ( return
   . (fdTConsName .~ "RecordF")
   . (fdTypes %~ ("f":))
   )
   [''Record]
   (const (Just applicativeBCR))
   (const [])
 )

deriving instance Show (RecordF Maybe)
deriving instance Eq (RecordF Maybe)
deriving instance Show (RecordF [])
deriving instance Eq (RecordF [])

recordFSpec =
  describe "Parametric records" $ do
    it "builds an applicative version " $ do
      aRecordToRecordF (Record "T-Shirt" 7) `shouldBe` Identity (RecordF (Just "T-Shirt") (Just 7))
    it "traverses when all values are present" $ do
      aRecordFToRecord (RecordF (Just "T-Shirt") (Just 7)) `shouldBe` Just (Record "T-Shirt" 7) 
    it "doesn't traverse when on value is missing" $ do
      aRecordFToRecord (RecordF (Just "T-Shirt") Nothing) `shouldBe` Nothing
    it "generates copy" $ do
      aRecordFToRecordF (RecordF (Just "T-Shirt") (Just 7))  `shouldBe` Identity (RecordF ["T-Shirt"] [7])
    it "traverse ZipList" $ do
      aRecordFToRecord (RecordF ["T-Shirt", "Cap"] [7, 2.5])  `shouldBe`
        ZipList [(Record ("T-Shirt") 7), (Record ("Cap") 2.5 )]

-- * Many to Many
data AB = AB { a :: Int, b :: Maybe Int} deriving (Eq, Show)
data C = C { c :: Int } deriving (Eq, Show)
-- Transforms AB,C to A,BC
-- data A {a :: Int}, data BC { b :: Int, c :: Int }
$(metamorphosis 
  (\fd -> [ fd & (case _fdFieldName fd of
                    Just "a" -> fdTConsName .~ "A"
                    Just "b" -> fdTConsName .~ "BC"
                    Just "c" -> (fdTConsName .~ "BC") . (fdPos .~ 3)
                 )
          ]
  )
 [''AB, ''C]
 (const (Just applicativeBCR))
 (const [''Show, ''Eq])
 )
manyToManySpec = describe "Many to Many" $ do
  it "splits from (AB,C) to (A,BC)" $ do
    aAB'CToA'BC (AB 1 (Just 2) ) (C 3) `shouldBe` ((Identity (A 1), Identity (BC (Just 2) 3)))
  it "extracts A" $  do
    aABToA (AB 1 (Just 2)) `shouldBe` Identity (A 1)
  it "sets C into BC" $ do
    aBC'CToBC (BC (Just 1) 0 ) (C 3) `shouldBe` Identity (BC (Just 1) 3)
  it "used Nothing when value are missing" $ do
    aCToBC (C 3) `shouldBe` Identity (BC Nothing 3)
  it "extracts C from a BC" $ do
    aBCToC (BC Nothing 7) `shouldBe` Identity (C 7)

-- * Types to Sum
data CInt = CInt Int deriving (Show, Eq)
data CString = CString String deriving (Show, Eq)
data CDouble = CDouble Double deriving (Show, Eq)
--  data SumC = SInt Int | SString String | SDouble Double
$(metamorphosis
 ( (:[])
   . (fdTypeName .~ "SumC")
   . (fdConsName %~ (("S" ++) . tail))
 )
 [''CInt, ''CString, ''CDouble]
 (const (Just applicativeBCR))
 (const [''Show, ''Eq]) 
 )
toSumSpecs = describe "To sum" $ do
  context "use the correct constructor" $ do
    it "SInt" $ do
      aCIntToSumC (CInt 3) `shouldBe` Identity (SInt 3)
    it "SDouble" $ do
      aCDoubleToSumC (CDouble 4.5) `shouldBe` Identity (SDouble 4.5)
    it "SDouble" $ do
      aCStringToSumC (CString "foo") `shouldBe` Identity (SString "foo")
  context "extract an CInt" $ do
    it "if possible" $ do 
      aSumCToCInt (SInt 5) `shouldBe` (Just (CInt 5))
    it "if not possible" $ do 
      aSumCToCInt (SDouble 4.5) `shouldBe` Nothing

  it "extract twos at the same time" $ do
    aSumCToCDouble'CInt (SDouble 4.5) `shouldBe` (Just (CDouble 4.5), Nothing)

  it "extract all at the same time" $ do
    aSumCToCDouble'CInt'CString (SInt 7) `shouldBe` (Nothing, Just (CInt 7), Nothing)

-- * Types to Enum
--  data EnumC = EInt | EString | EDouble 
$(metamorphosis
 ( (:[])
   . (fdTypeName .~ "EnumC")
   . (fdConsName %~ (("E" ++) . tail))
   . (fdFieldName .~ Nothing)
   . (fdTypes .~ [])
 )
 [''CInt, ''CString, ''CDouble]
 (const Nothing)
 (const [''Show, ''Eq, ''Enum, ''Bounded])
 )
toEnumSpecs = describe "To enum" $ do
  it "defines all contructors" $ do
    -- @TODO should be Eint, EString, EDouble
    [minBound..maxBound] `shouldBe` [EDouble, EInt, EString]
  it "convert to the correct constructor" (pendingWith "TODO")
  -- CIntTo
     

-- * Mapping over fields
-- This is only a hack to see how to map over all the fields.
-- The main API needs to be changed
$(metamorphosis
 ( (:[])
   . (fdTConsName .~ "ShowProduct")
 )
 [''Product]
 (\n -> if n == "ProductToShowProduct" then (Just (monoidPureBCR "show")) else Nothing)
 (const [])
 )
monoidSpecs = describe "To Monoid" $ do
  it "shows" $ do
    mpProductToShowProduct (Product "style" "var" 4.5 17) `shouldBe` ["\"style\"", "\"var\"", "4.5", "17"]
  it "" (pendingWith ("rewrite API"))



    
  
spec = do
  styleSpecs
  recordFSpec
  manyToManySpec
  toSumSpecs
  toEnumSpecs
  monoidSpecs


 
