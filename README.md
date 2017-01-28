# Bash 'eval' is a really bad idea
Just don't do it.

# Requirements
A *nix machine with `nc` (netcat) installed.

# Running it
./really-bad-idea.sh

# Using it
curl '127.0.0.1:8080/api/update'
curl '127.0.0.1:8080/api/delete'

# Abusing it
curl '127.0.0.1:8080/api/update/$(touch${IFS}/tmp/blam.txt)'
