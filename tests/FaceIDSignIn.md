# Face ID sign-in device checks

Use a physical iPhone with Face ID enrolled and a test account. These checks
require device interaction and have not been run by the coding agent.

1. Sign in with email, open Menu > Account, and enable Sign in with Face ID.
   Approve Face ID. The toggle should become enabled only after success.
2. Terminate and relaunch Stats. Face ID should start automatically without a
   button tap. Account data must remain unavailable until
   Sign in with Face ID succeeds. Successful authentication restores the same
   account and the server-verified permissions.
3. Cancel Face ID, then retry. Cancellation must leave the sign-in form visible;
   retry must work. Also test failed recognition and biometric lockout.
4. Deny Face ID access in Settings. Email sign-in must still work. Signing in
   with email clears the old biometric setup; enable it again from Account.
5. Disable the toggle while signed in, then terminate and relaunch. The normal
   remembered session should work without a biometric prompt.
6. Enable Face ID and log out. Account data must be cleared, and the sign-in
   screen must offer Face ID without opening the email keyboard. Tap Face ID
   and verify the same account is restored. Repeat after terminating and
   relaunching while logged out. Cancel Face ID and confirm email still works.
   Disable Face ID before logging out: the saved sign-in must be removed and
   the old server token revoked. Account deletion must also remove Face ID.
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

12. Complete email-code sign-in, log out, and focus the email field. The last
    successfully verified address should appear as a tappable button above the
    keyboard; tapping it fills the field without sending a code. Repeat after
    relaunch. A failed verification must not replace the saved address. Verify
    a different email and confirm the suggestion changes. Delete a disposable
    account and confirm the suggestion is cleared.

13. With Face ID disabled, relaunch with a valid saved session. It should restore
    the account without showing the login form. Relaunch offline: show a retry
    message, retain the saved credential, and keep account data hidden. Reconnect
    and tap Try again; the account should open without another email code.
14. Cancel automatic Face ID. Background and foreground the app: it must not
    repeatedly prompt. Manual Face ID retry should work. Logging out while the
    app is running must not immediately trigger automatic Face ID.
15. With Face ID disabled, revoke the saved server session and relaunch online.
    The rejected credential must be cleared; signing in again must still work.
