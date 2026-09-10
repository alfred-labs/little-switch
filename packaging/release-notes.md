## Fixes

**Agent tools work again through providers that rename grouped tools.** Some backends flatten grouped tool names or answer with a near-miss spelling; the gateway now restores the exact tool identity, so spawning and waiting for agents succeeds where it previously failed. Saving a provider runs a one-call namespace probe and shows the verdict in the editor.

**Custom routing headers reach the provider again.** Header entries configured on a provider are forwarded with every upstream request.
