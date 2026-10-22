# Privacy and listing worksheet

Prepared October 21, 2026 from the local source. These are proposed App Store
Connect answers, not a claim they have been saved or published there.

## App privacy

The app transmits data to the website and optional OpenAI services. Do not use
“Data Not Collected.” Declare the following as **linked to the user**, used for
**App Functionality**, and **not used for tracking**, matching the bundled
manifest. These are based on actual fields and behavior, including optional
fields; update the answers if live hosting/provider practices differ.

| App Store data type | Reason in this app |
| --- | --- |
| Name | Account and player names |
| Email Address | Account sign-in and optional roster email |
| User ID | Login names, account IDs, provider IDs |
| Photos or Videos | Selected player/reference photos and generated pictures |
| Other User Content | Comments, prompts, descriptions, recaps, flyers, and edits |
| Customer Support | Content reports and support correspondence |
| Product Interaction | Account activity and feature-operation records |
| Other Data | Birth dates and other optional profile details; hosting network records |
| Fitness | Volleyball participation, scores, performance and rankings |
| Health | Optional player height |
| Precise Location | A manually entered specific court or venue may identify attendance |
| Coarse Location | A manually entered broader game area |

There is no device GPS request or HealthKit integration. Manual collection still
counts. Face ID/Touch ID biometrics stay on the device; uploaded face photos are
separate content. There is no advertising or cross-company ad tracking in the
reviewed source. Do not claim other purposes such as Analytics or Marketing
unless the actual service uses the data that way. Confirm hosting logs and
third-party handling before publishing the answers.

Apple's [data-type and purpose definitions](https://developer.apple.com/app-store/app-privacy-details/)
govern the questionnaire. The privacy manifest does not automatically publish the
App Store nutrition label.

## AI disclosure and retention

This version uses OpenAI for app/web generation and moderation. Consent names
the provider and data types; permission starts off and is revocable. It covers
information already stored in selected games/profiles as well as new prompts.
Ordinary game entry does not require OpenAI permission. A background request must
check the creator's current permission before processing/publication.

OpenAI requests use API services; Responses storage is disabled. That does not
mean zero retention: provider abuse monitoring and applicable service policies
still apply. Gemini is disabled for app/web requests, including fallback. Do not
enable another provider without updating disclosure, consent, and this worksheet.

Confirm an actual restricted-backup/access-log retention schedule and an erasure
procedure with the hosting operator. The policy intentionally makes no invented
day-count promise. Complete that operational decision before launch.

## Price, storefronts, age rating, and rights

- **User-approved price: free.** No in-app purchases/subscriptions are implemented.
- **User-approved availability: worldwide**, meaning all eligible App Store
  storefronts. Complete any territory-specific developer/trader or distribution
  questions App Store Connect requests; global availability is not yet saved.
- Category: Sports. The app is not a medical device and makes no medical advice
  or treatment claims. Do not select the Kids category.
- Declare user-generated content: players can create and share text/images.
  Inspect the live public content and answer frequency questions truthfully.
  Do not assume a 4+ rating just because this is a sports app.
- Assess the current Social Media and Messaging/Chat definitions against share
  links, public content, and comments; the app has no direct chat feature. Do not
  claim an under-13 restriction or age assurance that the app does not implement.
- There is no arbitrary URL entry/search browser in this app. Embedded views
  restrict authenticated navigation to the website; external links open outside
  that view. Check the final web content before declaring unrestricted access.
- Confirm rights to existing player photos, names, generated content, logos, and
  listing screenshots. A policy telling users to obtain permission is not proof
  that all existing public assets have permission.
- Confirm the actual release option in App Store Connect. The previous snapshot
  recorded automatic release; this task did not change it.

Use Apple's current [age-rating definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/)
and accept the resulting regional ratings. Do not guess a numeric rating or
claim a restriction based only on the privacy-policy wording.

## Screenshots and metadata

Use real screenshots of the final app with fictional data, without secret tokens
or other people's private records. Suggested set: rankings, game history, Add
game, player stats, and an approved recap/flyer. Avoid empty/loading/error screens.

Apple currently lists iPhone with Dynamic Island (medium display) and iPad
13-inch as required slots for this universal app. Examples of accepted portrait
sizes are 1206×2622 for iPhone and 2064×2752 for iPad. Check the actual required
slots at upload time; images must not contain transparency. See [Apple's screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).

Set the support and privacy URLs from `submission-draft.json` only after they are
deployed and reachable without login. Verify metadata reflects the final app,
including optional AI permission, account features, and internet requirements.
Native sign-in currently offers email/password and Apple, not a Google button.

The source sets `ITSAppUsesNonExemptEncryption` to false for system-provided
authentication/HTTPS. Reconfirm that the final binary still uses only exempt
encryption and answer export-compliance questions accordingly. This worksheet
does not replace App Store Connect's validation or content-rights confirmation.
