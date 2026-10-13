SmartScreen reputation for Windows app developers - Windows apps | Microsoft Learn
Skip to main content
Skip to Ask Learn chat experience
This browser is no longer supported.
Upgrade to Microsoft Edge to take advantage of the latest features, security updates, and technical support.
Download Microsoft Edge
More info about Internet Explorer and Microsoft Edge
Table of contents
Exit editor mode
Ask Learn
Ask Learn
Reading mode
Table of contents
Read in English
Add
Add to Plans
Edit
Copy Markdown
Print
Note
Access to this page requires authorization. You can try signing in or changing directories.
Access to this page requires authorization. You can try changing directories.
SmartScreen reputation for Windows app developers
Feedback
Summarize this article for me
In this article
Microsoft Defender SmartScreen checks the reputation of downloaded files before allowing them to run. Understanding how reputation works can help avoid warnings when users download or run your files.
Tip
The simplest way to avoid SmartScreen warnings is to publish through the Microsoft Store. Store-distributed apps are signed by a Microsoft certificate and are never subject to SmartScreen download warnings. The remainder of this article applies to apps distributed outside the Store.
How SmartScreen reputation works
SmartScreen evaluates two signals when a user downloads and runs a file:
Publisher reputation — Is the file signed? Is the signing certificate from a known, trusted publisher?
File hash reputation — Has this specific file been downloaded by users without indications of malicious behavior?
A negative or unknown reputation for a file's hash or its publisher's certificate can cause warnings to show. Even when signed, a newly created binary could still show a SmartScreen warning until its hash or publisher certificate accumulates sufficient evidence of positive reputation.
When a file is not signed, SmartScreen reputation must build for each new version of your files, starting with zero reputation. Reputation cannot transfer from previous versions unless both were signed using the same publisher identity.
Certificate options and their SmartScreen implications
To reduce the likelihood of interruption, you should sign all of your files with a valid certificate.
Certificate type
First-download SmartScreen behavior
Microsoft Store
✅ No warning — covered by Microsoft's certificate
Valid Certificate (OV/EV)
⚠️ Warning — app flagged as unrecognized until reputation accumulates; verified publisher name is displayed
No signature
⚠️ Warning — "Windows protected your PC"; User must choose "Run anyway" before the app can run. Enterprise policy can prevent  continuation entirely.
Self-signed Certificate
⚠️ Warning — Same behavior as no signature
Note
EV certificates no longer bypass SmartScreen. Years ago, signing files with an Extended Validation (EV) code signing certificate would result in positive SmartScreen reputation by default, but this behavior no longer exists. EV certificates may matter for enterprise procurement, but they no longer impact SmartScreen behavior. Paying a premium for EV solely to avoid SmartScreen warnings is no longer justified.
Microsoft Store (recommended)
Apps published through the Microsoft Store are re-signed by Microsoft and carry full reputation. Users will never see a SmartScreen warning for a Store-installed app.
Artifact Signing (formerly Trusted Signing)
Artifact Signing (formerly Trusted Signing) is Microsoft's recommended code signing service for non-Store distribution:
Cost — Starts at $9.99/month. See Artifact Signing pricing.
No hardware token required — integrates directly with CI/CD pipelines (GitHub Actions, Azure DevOps)
Identity validation required — Microsoft validates your identity before issuing certificates
SmartScreen behavior — reputation accumulates over time based on download volume and behavior
What to expect when you publish a new app
First downloads: Users may see a SmartScreen prompt indicating the app is unrecognized. For signed apps, the publisher name is displayed. Users should proceed only after verifying the source.
As downloads accumulate: SmartScreen reputation builds up automatically. The prompt will stop appearing once the file hash has sufficient download history. There is no exact threshold, but it can take several weeks and hundreds of clean installs from a wide audience.
New version: Signing files using a trusted certificate can allow certificate reputation to build, potentially avoiding warnings on new files signed by the same trusted certificate. Unsigned files must build reputation anew with every update.
There is no need (or mechanism) to manually submit a file for SmartScreen reputation review for consumer endpoints. Reputation builds organically through download volume.
Note
Enterprise environments may have different SmartScreen behavior depending on policy configuration; for example, the ability to bypass a SmartScreen warning may be disabled. Enterprises may distribute files from Trusted Intranet locations not subject to SmartScreen review. Enterprise IT administrators may optionally submit files for review via the Microsoft Security Intelligence portal. This can accelerate trust for internal or managed deployments.
Minimizing SmartScreen warnings in practice
Publish to the Microsoft Store where feasible — this is the most reliable way to avoid warnings entirely
Sign every release — unsigned files cannot inherit a positive reputation from the signing certificate
Do not modify signed files - Avoid modifying files after signing as doing so can break the signature depending on client configuration
Do not sign potentially unwanted applications - Avoid signing any file which exhibits malicious or potentially unwanted application behavior, or the certificate may develop negative reputation
Use a consistent signing identity — changing your signing certificate affects the publisher trust signal
Communicate with early adopters — for new apps, let beta users know they may see a SmartScreen prompt on first download, and that they should only proceed after verifying the publisher and confirming they trust the download source
Tip
On Windows 11 devices, the Smart App Control feature may supersede SmartScreen Application Reputation. Smart App Control will block execution of unsigned files unless the file has a positive reputation. Smart App Control signature checks apply to all executable files, not just those downloaded from the Internet.
Related content
Choose a distribution path for your Windows app
Current status of Windows app distribution features
Sign an app package using SignTool
Artifact Signing (formerly Trusted Signing) documentation
Microsoft Trusted Root Program requirements
Collaborate with us on GitHub
The source for this content can be found on GitHub, where you can also create and review issues and pull requests. For more information, see our contributor guide.
Windows developer
Open a documentation issue
Provide product feedback
Feedback
Was this page helpful?
Yes
No
No
Need help with this topic?
Want to try using Ask Learn to clarify or guide you through this topic?
Ask Learn
Ask Learn
Suggest a fix?
Additional resources
Last updated on
2026-05-06
In this article
Was this page helpful?
Need help with this topic?
Want to try using Ask Learn to clarify or guide you through this topic?
Ask Learn
Ask Learn
Suggest a fix?
en-us
Your Privacy Choices
Theme
Light
Dark
High contrast
AI Disclaimer
Previous Versions
Blog
Contribute
Privacy
Consumer Health Privacy
Terms of Use
Trademarks
© Microsoft 2026