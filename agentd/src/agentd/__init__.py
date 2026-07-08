"""PetOS agent runtime.

A local sidecar that hosts a manager agent orchestrating read-only worker
agents. It talks to the PetOS macOS app over a loopback WebSocket. In phase 1
agents may only OBSERVE the system (read-only); they never edit or execute.
"""

__version__ = "0.1.0"
