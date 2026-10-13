Code signing options for Windows app developers - Windows apps | Microsoft Learn
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
Code signing options for Windows app developers
Feedback
Summarize this article for me
In this article
If you publish your app as an MSIX package through the Microsoft Store, code signing is free and handled for you automatically — Microsoft re-signs the package after certification and you don't need to purchase or manage a certificate. If you publish as an MSI/EXE installer through the Store, you are responsible for Authenticode signing your installer before submission. Everything else in this article applies to apps distributed outside the Microsoft Store.
Comparison at a glance
Option
Cost
Availability
SmartScreen behavior
Store eligible
Best for
Microsoft Store (MSIX) — Store re-signs your package
Free
Worldwide
✅ No warnings
✅ Yes
Recommended for most new apps
Microsoft Store (MSI/EXE installer) — publisher must sign
Cert chaining to Trusted Root Program CA required (varies by CA)
Worldwide
✅ No SmartScreen prompts during Store install (UAC may still appear)
✅ Yes
Existing Win32 apps submitting via MSI/EXE installer path
Azure Artifact Signing (formerly Trusted Signing)
~$9.99/month
Organizations: USA, Canada, EU, UK. Individuals: USA and Canada only
⚠️ Reputation builds over time; initial warnings expected
❌ No
Recommended for non-Store distribution
OV certificate (from a CA such as DigiCert, Sectigo)
$150–300/year
Worldwide
⚠️ Same as Azure Artifact Signing — reputation builds over time
❌ No
Developers who can't use Azure Artifact Signing, or who prefer traditional CAs
EV certificate
$400+/year
Worldwide
⚠️ Same as OV since 2024 — no longer instant bypass
❌ No
No longer recommended specifically for SmartScreen bypass
Self-signed certificate
Free
—
❌ Blocks installation for public users
❌ No
Dev/testing only, or enterprise with managed certificate trust
No signature
Free
—
❌ Strong SmartScreen block; enterprises may block entirely
❌ No
Not recommended for public distribution
Microsoft Store — MSIX submissions: no signing needed
Publishing an MSIX package through the Microsoft Store is the recommended distribution path for most Windows apps. Microsoft re-signs your package automatically, meaning users never see a SmartScreen warning and you never need to purchase or renew a certificate.
Note
If you're submitting a Win32 MSI or EXE installer to the Store (rather than an MSIX package), Microsoft does not re-sign your installer. The installer and its PE files must be signed with a certificate chaining to a CA in the Microsoft Trusted Root Program — self-signed certificates are not accepted. See App package requirements for MSI/EXE.
Create a free developer account at storedeveloper.microsoft.com. After you register, use Partner Center to submit your app and manage its listing.
→ Publish your app to the Microsoft Store
Azure Artifact Signing (formerly Trusted Signing) — recommended for non-Store distribution
Azure Artifact Signing (formerly Trusted Signing) is Microsoft's recommended code signing service for developers who distribute apps outside the Store.
Key details:
Cost: Approximately $9.99/month — significantly less than a traditional OV or EV certificate
Identity validation: Microsoft validates your organization or individual identity before issuing certificates; plan for a few business days for verification
No hardware token required: Signing integrates directly with CI/CD pipelines (GitHub Actions, Azure DevOps, and others) — you don't need a physical USB token
SmartScreen behavior: New files can show a SmartScreen warning until they accumulate sufficient reputation. Azure Artifact Signing does not provide instant SmartScreen trust, but signing consecutive releases with a consistent publisher/signing identity lets publisher reputation build over time, so later releases can inherit trust. See SmartScreen reputation.
Important
Geographic limitation: Azure Artifact Signing is available to organizations in the USA, Canada, the European Union, and the United Kingdom. Individual developers are currently limited to the USA and Canada. If you are an individual developer outside those regions, see OV certificates below.
→ Azure Artifact Signing documentation
→ Sign an MSIX package using SignTool
OV certificates — traditional CA option
Organization Validated (OV) certificates from a Certificate Authority (CA) such as DigiCert, Sectigo, or GlobalSign are a well-established option for code signing. They are the right choice when:
You are located outside the USA, Canada, the EU, or the UK (organizations); or outside the USA or Canada (individual developers) and cannot use Azure Artifact Signing
Your organization already has a relationship with a specific CA
Your enterprise customers require a certificate from a particular CA
Key details:
Cost: Typically $150–300/year depending on the CA and certificate tier
Identity validation: The CA validates your organization's legal identity before issuing the certificate; allow several business days
HSM requirement: As of June 2023, the CA/Browser Forum requires private keys for OV certificates to be stored on a hardware security module (HSM) or hardware token. Most CAs provide a compatible USB token or cloud HSM option.
SmartScreen behavior: Expect SmartScreen prompts for new files until reputation is established. As with any trusted certificate, signing releases with a consistent identity lets publisher reputation accumulate across versions, rather than starting from zero each time.
OV certificates are a proven option and are functionally equivalent to Azure Artifact Signing for SmartScreen purposes. If you are in the US or Canada (or an organization in the EU or UK), Azure Artifact Signing is typically more cost-effective and integrates more smoothly with automated build pipelines.
EV certificates — no longer recommended for SmartScreen
Extended Validation (EV) certificates previously bypassed SmartScreen entirely on first download, making them the go-to choice for new apps with no reputation. That behavior was removed in 2024. EV-signed files now go through the same reputation-building process as OV certificates.
What this means:
If you already have an EV certificate, it is still valid and functional for signing — keep using it until it expires
EV certificates still require more rigorous identity validation, which may matter for enterprise procurement or other trust contexts
Paying the EV premium ($400+/year) solely to avoid SmartScreen warnings is no longer justified — you will still see the same warnings as with an OV certificate
→ SmartScreen reputation for developers for full details on how reputation builds and what users see
Self-signed certificates — dev and testing only
A self-signed certificate is not trusted by Windows by default and will trigger a strong SmartScreen block for any user who hasn't manually installed the certificate as a trusted root. This makes self-signed certificates unsuitable for public distribution.
Appropriate uses:
Local development and testing — you control the machine and can install the certificate manually
Enterprise internal distribution — your IT department can deploy the certificate as a trusted root via Intune or Group Policy, allowing managed devices to install the app silently
→ Sign an MSIX package using SignTool
Open source: SignPath Foundation
If your project is open source, SignPath Foundation offers free code signing for qualifying open-source projects. The program provides OV-level certificate signing through a managed pipeline. Check the SignPath Foundation website for eligibility requirements and the application process.
Related content
SmartScreen reputation for developers
Choose a distribution path for your Windows app
Sign an MSIX package using SignTool
Azure Artifact Signing (formerly Trusted Signing) documentation
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
2026-08-29
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