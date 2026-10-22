# Make process analysis the primary package

The project now serves historical process-log discovery, finite-reference trace alignment
and interval performance analysis. These capabilities use independent LogEvent/CaseTrace
types and do not call the sequence NFA. The prior detector is retained in an optional
`sequence` subpackage, preserving source history and existing semantics while giving
the new root package a distinct domain and dependency boundary. Retaining the detector
in the root would make the renamed project misleadingly appear to have the same primary
API; deleting it would discard useful, tested functionality and its development history.
