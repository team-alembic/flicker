# Ash logs each create/read at :debug by default — quiet by default so
# `Dev.Music.seed!/0` (called in most Ash-provider test setups) doesn't
# drown out actual test output; bump back down locally when debugging.
Logger.configure(level: :info)

ExUnit.start()
