# Contributing

Thanks for your interest! You can write issues and pull requests **in any language**. English is the easiest for everyone to read, but it is not required.

## Reporting a problem

Open a [bug report](https://github.com/carlosnakazawa/windows-health-and-update/issues/new?template=bug_report.yml). The most useful information is:

- the Windows version, edition and build (`winver`, or the first lines of the script output);
- the PowerShell version (`$PSVersionTable.PSVersion`);
- the JSON report from `%ProgramData%\WindowsHealthAndUpdate\Logs`. It contains no personal data apart from the computer's Windows details, but review it before posting.

## Suggesting an idea

Open a [feature request](https://github.com/carlosnakazawa/windows-health-and-update/issues/new?template=feature_request.yml). Tell us which Windows versions it concerns.

## Code changes

1. Fork the repository and create a branch.
2. Keep the `.ps1` files **ASCII-only** and compatible with **Windows PowerShell 5.1** and PowerShell 7.
3. Add or update tests in `tests/` when you change logic.
4. Run the checks locally:

   ```powershell
   Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
   Invoke-Pester ./tests -Output Detailed
   ```

5. Open a pull request describing what changed and on which Windows versions you tested it.

### Updating Windows lifecycle dates

End-of-support dates live in `Get-WindowsLifecycleData` in `Invoke-WindowsMaintenance.ps1`. When Microsoft publishes a new release, add its rows (one per servicing track) with a link to the official [Windows release health](https://learn.microsoft.com/windows/release-health/) page in the pull request, and update the support table in the READMEs.

## Translations

The documentation is available in English (the reference), Português (Brasil), Español, Français, Deutsch, Italiano, Русский, 日本語, 한국어 and 简体中文.

- **Fix a translation:** edit the file in `docs/` and open a pull request. Native speaker reviews are very welcome.
- **Add a language:** copy `README.md` to `docs/README.<language-code>.md` (for example `README.hi.md`), translate it, keep the code blocks unchanged except for the comments, and add the new language to the language bar at the top of **every** README. A test checks that all language links resolve.
- **Update translations:** when `README.md` changes, a translation that is not updated yet is fine. Each translation says that the English version is the reference.
