# Copyright (c) 2026 Santander Group
# SPDX-License-Identifier: Apache-2.0
#
# PSScriptAnalyzer configuration for ralph.
#
# ralph-loop.ps1 is a single-file, standalone automation script -- not a
# reusable PowerShell module or a set of public cmdlets. The following rules
# encode cmdlet/module *authoring conventions* (ShouldProcess support, singular
# nouns) that are appropriate for shipped modules but are false positives for an
# internal script's private helper functions. They are excluded here; every
# other Warning and Error rule still gates CI.
#
# PSUseBOMForUnicodeEncodedFile is also excluded: ralph-loop.ps1 carries a Unix
# shebang (#!/usr/bin/env pwsh) for cross-platform execution, and a leading
# UTF-8 BOM would break shebang resolution on Linux/macOS. The file is valid
# UTF-8 (no BOM) by design.
@{
    Severity = @('Warning', 'Error')
    ExcludeRules = @(
        'PSUseShouldProcessForStateChangingFunctions',
        'PSUseSingularNouns',
        'PSUseBOMForUnicodeEncodedFile'
    )
}
