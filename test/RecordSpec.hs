{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
module RecordSpec where

import Control.Lens
import Test.Hspec
import Metamorphosis
import Control.Monad
import Data.Functor.Identity

data Product = Product { style :: String
                       , variation :: String
                       , price :: Double
                       , quantity :: Int
                       } deriving (Show, Eq)

p = Product "style" "var" 15.50 2 

-- | Generates Style type
-- data Style = Style { style :: String
--                    , price :: Double
--                    } deriving (Show, Eq)
$(metamorphosis'
   ( (\fd -> if fd ^. fdFName `elem` map Just ["variation", "quantity"]
             then []
             else [fd])
   . (fdTName .~ "Style")
   . (fdCName .~ "Style")
   )
   [''Product] ["Style"]
 )

deriving instance Show Style
deriving instance Eq Style
productToStyle = runIdentity . productToStyleA
styleInProduct = undefined

 
styleSpecs = 
  describe "Style" $ do
    it "gets from a p" $ do
      productToStyle p `shouldBe` (Style "style" 15.50)
    it "sets to a p" $ do
      styleInProduct (Style "new" 7) p `shouldBe` (Product "new" "var" 7.0 2)

-- | Generates ProductF type
-- data ProductF f = ProductF { style :: f String
--                            , variation :: f String
--                            , price :: f Double
--                            , quantity :: f Int
--                            } deriving (Show, Eq)

$(metamorphosis'
   ( return
   . (fdTName .~ "ProductF")
   . (fdCName .~ "ProductF")
   . (fdTypes %~ ("f":))
   )
   [''Product] ["ProductF"]
 )
deriving instance Show (ProductF Maybe)
deriving instance Eq (ProductF Maybe)

productFSpecs =
  describe "ProductF -- parametric functor" $ do
    it "gets from a p" $ do
      productToProductF p `shouldBe` (ProductF (Just "style") (Just "var") (Just 15.50) (Just 2))
    it "extracts from a productM" $ do
      productFToProductA (productToProductF p) `shouldBe` Just p

-- | Generates ProductM type
-- data ProductM = ProductF { style :: String
--                          , variation :: String
--                          , price :: [ Double ]
--                          , quantity :: Int
--                          } deriving (Show, Eq)
productToProductF :: Product -> ProductF Maybe
productToProductF = runIdentity  . productToProductFA

$(metamorphosis'
   ( return
   . (fdTName .~ "ProductM")
   . (fdCName .~ "ProductM")
   . (\fd -> if fd ^. fdFName == Just "price"
                        then fdTypes %~ ("[]" : ) $ fd
                        else fdTypes %~ id $ fd )
   )
   [''Product] ["ProductM"]
 )
deriving instance Show ProductM 
deriving instance Eq ProductM 

productToProductM = runIdentity . productToProductMA


productMSpecs =
  describe "ProductM -- one functor" $ do
    it "gets from a p" $ do
      productToProductM p `shouldBe` (ProductM "style" "var" [15.50] 2)
    it "extracts from a productM" $ do
      productFToProductA (productToProductF p) `shouldBe` Just p
  
-- * 
-- Using two functors parameter we can get different responses
-- by converting to different functor
-- data ProductF2 f g =
--   ProductF2 { style :: f String
--             , variation :: g String
--             , price :: Double
--             , quantity :: Int
--             }

$(metamorphosis'
   ( return
   . (\fd -> fdTypes %~ (case _fdFName fd of
                              Just "style" -> ("f":) 
                              Just "variation" ->  ("g":)
                              _ -> id
                        ) $ fd
     )
   . (fdTName .~ "ProductF2")
   . (fdCName .~ "ProductF2")
   )
   [''Product] ["ProductF2"]
 )
$(generateExtract return [''ProductF2] [''ProductF2] "productF2ToProductF2A")

deriving instance Show (ProductF2 [] [])
deriving instance Eq (ProductF2 [] [])
deriving instance Show (ProductF2 [] Identity)
deriving instance Eq (ProductF2 [] Identity)
deriving instance Show (ProductF2 Identity [])
deriving instance Eq (ProductF2 Identity [])

productF2Specs =
  describe "ProductF2" $ do
    let pf = ProductF2 ["A", "B"] ["red", "black"] 7 1
    it "extracts bot fields" $ do
        productF2ToProductA pf `shouldBe` [ Product "A" "red" 7 1
                                          , Product "A" "black" 7 1
                                          , Product "B" "red" 7 1
                                          , Product "B" "black" 7 1
                                          ]
    it "extracts styles" $ do
      productF2ToProductF2A pf `shouldBe` [ ProductF2 (Identity "A") ["red", "black"] 7 1
                                          , ProductF2 (Identity "B") ["red", "black"] 7 1
                                          ]
    it "extracts variations" $ do
      productF2ToProductF2A pf `shouldBe` [ ProductF2 ["A", "B"] (Identity "red") 7 1
                                          , ProductF2 ["A", "B"] (Identity "black") 7 1
                                          ]

spec :: Spec
spec = do
  styleSpecs
  productFSpecs
  productMSpecs
  productF2Specs





-- main  :: IO ()
