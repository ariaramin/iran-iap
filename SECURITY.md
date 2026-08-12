# Security policy

## Reporting a vulnerability

Please do not open a public GitHub issue for a vulnerability that could expose purchase verification, entitlement, credential, or store-billing weaknesses.

Until a dedicated security contact is configured, use GitHub's private security advisory flow for the repository.

## Security model

`iran_iap` is a client billing integration layer. It does not make a mobile device a trusted authorization boundary.

For valuable entitlements:

- verify purchase evidence on a trusted backend;
- keep server credentials and private keys off the client;
- make entitlement grants idempotent;
- avoid logging purchase tokens, raw receipts, signatures, or user secrets;
- consume consumables only after durable server-side state is recorded.
