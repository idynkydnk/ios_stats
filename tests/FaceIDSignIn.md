# Face ID sign-in device checks

Use a physical iPhone with Face ID enrolled and a test account. These checks
require device interaction and have not been run by the coding agent.

1. Sign in with email, open Menu > Account, and enable Sign in with Face ID.
   Approve Face ID. The toggle should become enabled only after success.
2. Terminate and relaunch Stats. Account data must remain unavailable until
   Sign in with Face ID succeeds. Successful authentication restores the same
   account and the server-verified permissions.
3. Cancel Face ID, then retry. Cancellation must leave the sign-in form visible;
   retry must work. Also test failed recognition and biometric lockout.
4. Deny Face ID access in Settings. Email sign-in must still work. Signing in
   with email clears the old biometric setup; enable it again from Account.
5. Disable the toggle while signed in, then terminate and relaunch. The normal
   remembered session should work without a biometric prompt.
6. Enable Face ID, log out, and relaunch. No saved Face ID sign-in should remain.
   Repeat with account deletion on a disposable account.
7. Enable Face ID, then change the enrolled face. The saved credential must no
   longer unlock; email sign-in must recover access.
8. Enable Face ID, terminate the app, disconnect the network, and attempt Face
   ID sign-in. It must not grant access without server verification. Reconnect
   and retry; the saved credential should still work.
9. Invalidate the server session and relaunch. Face ID must not restore access;
   use email to establish a new session.
10. Sign in with a different account using email. The previous account's saved
    Face ID credential must be removed.
11. Repeat enable, relaunch, cancel, disable, and logout on a Touch ID device.
    Labels and prompts should use Touch ID.

This feature protects the remembered credential on app launch. It does not
lock an already-open session when the app briefly goes into the background.
