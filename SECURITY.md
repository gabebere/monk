# Security policy

## Reporting a vulnerability

Please do not publish an exploitable bypass or private user data in a public issue. Use GitHub's private vulnerability reporting for this repository when available, or contact the repository owner privately through the contact information on their GitHub profile.

Include the affected platform, OS version, Monk commit or release, reproduction steps, and the practical impact. Reports involving an enforcement bypass are most useful when they distinguish ordinary user actions from actions that require administrator access, developer tools, or physical recovery access.

## Security boundary

Monk is a focus commitment tool, not parental-control or endpoint-security software. Mobile enforcement relies on Apple's Family Controls and Managed Settings frameworks. Desktop enforcement runs in the signed-in user's context; an administrator can ultimately terminate or remove it.

Focus metadata syncs through the user's private CloudKit database. The project has no developer-operated sync server. Screen Time selection tokens are platform-private data and should never be logged, uploaded to a public service, or committed to the repository.

Only the latest commit on the default branch is supported until versioned releases begin.
