# Reach the AWS Exit Proxy with an ephemeral key pair + /32 SSH, not SSM or EIC

`proxy-aws.sh` launches the EC2 Exit Proxy with **no IAM role**, imports a
locally-generated ephemeral key pair (`ec2 import-key-pair`, public key only),
locks a per-session security group to inbound `tcp/22` from the operator's
current `/32`, and tunnels with a plain `ssh -D 1080`. This mirrors the GCP
script's posture: credential-free box, key-only auth, throwaway instance.

Why this and not the AWS-native alternatives — the choice is forced by the IAM
permissions of the only identity available. Verified with `iam simulate-principal-policy`:

- **SSM (zero-inbound, the best design)** needs an instance profile and is
  blocked three ways: `iam:CreateRole`, `iam:PassRole`, and
  `ssm:StartSession` are all *implicitDeny*. The box could never assume the
  required role, the user could never pass it at launch, and the user could
  never open a session.
- **EC2 Instance Connect** (`ec2-instance-connect:SendSSHPublicKey`) is also
  *implicitDeny*. This is why the earlier EIC-based `proxy-aws.sh` never ran
  clean — its entire auth path is an action this user cannot call.
- The group grants `AmazonEC2FullAccess` + `IAMReadOnlyAccess` +
  `AmazonS3FullAccess` only. EC2 run/terminate/describe, security-group
  create/authorize/revoke/delete, and key-pair create/import/delete are all
  *allowed* — so the key-pair path is the one design that runs today with no
  admin involvement.

Cost / accepted trade-off: unlike SSM, the box keeps an egress public IP (it is
an Exit Proxy and must reach the internet) and a reachable — though `/32`-locked
— inbound SSH port. `RISKS.md` #2 is mitigated, not eliminated.

Upgrade path: if an admin later creates an SSM instance-profile role and grants
the user `iam:PassRole` on it plus `ssm:StartSession` /
`ssm:TerminateSession` / `ssm:DescribeInstanceInformation`, switch to
SSH-over-SSM (`ProxyCommand` → `aws ssm start-session --document-name
AWS-StartSSHSession`) and drop the public IP, the inbound rule, and the
security group entirely. The `ssh -D` tunnel and the Chrome extension are
unaffected by that swap.
