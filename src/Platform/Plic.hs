module Platform.Plic
  (Plic,
   ChangeMIP(..),
   plicSetIRQ,
   plicUpdateMIP,
   readPlic,
   writePlic,
   initPlic) where
import Data.Int
import Data.Bits
import Data.IORef

data ChangeMIP =
  Set | Reset | DoNothing deriving(Eq, Show)

data Plic = Plic { plicServedIrq :: IORef Int32,
                   plicPendingIrq :: IORef Int32}

-- The boolean indicate if we need to set/reset mip in the RV machine.
writePlic :: Plic -> Int32 -> Int32 -> IO ChangeMIP
writePlic plic offset val = do
  let servedIrqs = plicServedIrq plic
  case offset of
    0x200004 -> do -- PLIC_HART_BASE + 4
      let realval = val - 1
      if val < 32
        then do
        vServedIrqs <- readIORef servedIrqs
        writeIORef servedIrqs $ vServedIrqs .&. (complement $ shiftL 1 (fromIntegral realval))
        doUpdate <- plicUpdateMIP plic
        return doUpdate
        else do
        return DoNothing
    _ -> return DoNothing

-- The boolean indicate if we need to set/reset mip
readPlic :: Plic -> Int32 -> IO (Int32,ChangeMIP)
readPlic plic offset = do
  case offset of
    0x200000 -> do -- PLIC_HART_BASE
      return (0, DoNothing)
    0x200004 -> do -- PLIC_HART_BASE + 4
      vPendingIrqs <- readIORef $ plicPendingIrq plic
      vServedIrqs <- readIORef $ plicServedIrq plic
      let mask = vPendingIrqs .&. (complement vServedIrqs)
      if mask /= 0
        then do
        let i = undefined mask --todo ctz32?
        writeIORef (plicServedIrq plic) $ vServedIrqs .|. (shiftL 1 i)
        doUpdate <- plicUpdateMIP plic
        return (i + 1, doUpdate)
        else do
        return (0,DoNothing)
    _ -> return (0,DoNothing)

-- Interal function, used to compute if we need to tell the caller of read/write/set to set the MIP register.
plicUpdateMIP :: Plic -> IO ChangeMIP
plicUpdateMIP plic = do
  pendings <- readIORef $ plicPendingIrq plic
  served <- readIORef $ plicServedIrq plic
  if (pendings .&. (complement served)) /= 0
    then return Set
    else return Reset

-- Function called by different devices to raise an external
-- interrupt. Return if we need to setup mip.
plicSetIRQ :: Plic -> Int -> Int -> IO ChangeMIP
plicSetIRQ plic irqNum state = do
  let pendingIrqs = plicPendingIrq plic
  let mask = shiftL 1 (irqNum -1)
  if (state /= 0)
    then do
    vPendingIrqs <- readIORef pendingIrqs
    writeIORef pendingIrqs $ vPendingIrqs .|. mask
    else do
    vPendingIrqs <- readIORef pendingIrqs
    writeIORef pendingIrqs $ vPendingIrqs .&. (complement mask)
  plicUpdateMIP plic

initPlic :: IO Plic
initPlic = do
  pendings <- newIORef 0
  served <- newIORef 0
  return $ Plic {plicServedIrq = served, plicPendingIrq = pendings}

