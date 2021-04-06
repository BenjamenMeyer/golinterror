golinterror
===========

Golint cannot detect polymorphic usages; a simple type definition can throw it off so that it incorrectly reports that
fields in a structure are not used. This repository provides an example of this that can be easily reproduced.

The pattern used here is a common methodology employed for versioning parts of files, network messages, etc that grow
with new versions.
