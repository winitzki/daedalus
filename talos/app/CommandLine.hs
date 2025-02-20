
module CommandLine ( Options(..)
                   , Outfile(..)
                   , Mode(..)
                   , getOptions
                   ) where

import Options.Applicative

data Outfile = AllOutput FilePath | PatOutput FilePath

data Mode = SynthesisMode | SummaryMode | DumpCoreMode

data Options =
  Options { optSolver    :: FilePath
          -- Logging
          , optLogOutput :: Maybe FilePath
          , optLogLevel  :: Maybe Int
          -- Model generation
          , optNModels   :: Int
          , optSeed      :: Maybe Int
          , optOutfile   :: Maybe Outfile
          , optPrettyModel :: Bool
          , optProvFile  :: Maybe FilePath
          -- Prover options
          , optValidateModel :: Bool
          -- Debugging options
          , optMode :: Mode
          , optDDLEntry   :: Maybe String
          , optStrategy  :: Maybe String
          , optInvFile    :: Maybe FilePath          
          , optDDLInput  :: FilePath
          }

solverOpt :: Parser String
solverOpt = strOption
   ( long "solver"
  <> short 's'
  <> metavar "FILE"
  <> value "z3"
  <> showDefault
  <> help "Path to z3" )

logfileOpt :: Parser String
logfileOpt = strOption
   ( long "logfile"
  <> short 'L'
  <> metavar "FILE"
  <> help "Write log to FILE (default stdout)" )

loglevelOpt :: Parser Int
loglevelOpt = option auto
   ( long "log"
  <> short 'l'
  <> metavar "INT"
  <> help "Log verbosity (default don't log)" )

validateModelFlag :: Parser Bool
validateModelFlag = switch
  ( long "validate"
  <> short 'V'
  <> help "Tell solver to validate models" )

nModelsOpt :: Parser Int
nModelsOpt = option auto
   ( long "nmodels"
  <> short 'n'
  <> metavar "INT"
  <> value 1
  <> showDefault
  <> help "Number of models to produce." )

seedOpt :: Parser Int
seedOpt = option auto
   ( long "seed"
  <> short 'S'
  <> metavar "INT"
  <> help "Initial random seed" )

optPrettyOutput :: Parser Bool 
optPrettyOutput = switch
  ( long "pretty"
  <> help "Pretty-print model bytes and value to stdout"
  )

optProvOutput :: Parser String
optProvOutput = strOption
   ( long "prov-map"
     <> metavar "FILE"
     <> help "Write provenance to FILE" )

invFileOpt :: Parser FilePath
invFileOpt = strOption
   ( long "inverses"
     <> metavar "FILE"
     <> short 'i'
     <> help "Inverse annotations" )


allOutputOpt :: Parser String
allOutputOpt = strOption
   ( long "all-output"
  <> short 'o'
  <> metavar "FILE"
  <> help "A file to write all models into (default: stdout)." )

patOutputOpt :: Parser String
patOutputOpt = strOption
   ( long "output"
  <> short 'O'
  <> metavar "FILE-PATTERN"
  <> help "A collection of files to write models to.  The first '%' in the file name is replaced by the model number.  If there is no '%', an implicit '.%' is added to the end" )

modeOpt :: Parser Mode
modeOpt = flag' SummaryMode ( long "summary" <> help "Print out analysis results")
          <|> flag' DumpCoreMode ( long "dump-core" <> help "Print out intermediate core")
          <|> pure SynthesisMode -- defaultx
          
entryOpt :: Parser String
entryOpt = strOption
    ( long "entry"
    <> short 'e'
    <> metavar "FUNCTION-NAME"
    <> help "The entry point to use (default: 'Main')"
    )

strategyOpt :: Parser String
strategyOpt = strOption
    ( long "strat"
    <> short 't'
    <> metavar "STRATEGY-NAME"
    <> help "The synthesis strategy to use"
    )

options :: Parser Options
options = Options <$> solverOpt
                  <*> optional logfileOpt
                  <*> optional loglevelOpt
                  <*> nModelsOpt
                  <*> optional seedOpt
                  <*> optional ((AllOutput <$> allOutputOpt) <|> (PatOutput <$> patOutputOpt))
                  <*> optPrettyOutput
                  <*> optional optProvOutput
                  <*> validateModelFlag
                  <*> modeOpt
                  <*> optional entryOpt
                  <*> optional strategyOpt
                  <*> optional invFileOpt
                  <*> argument str (metavar "FILE")

opts :: ParserInfo Options
opts = info (options <**> helper)
  ( fullDesc
  <> header "talos - a daedalus-based input synthesiser." )

getOptions :: IO Options
getOptions = execParser opts
