"""Tests for the contract between the automation and the configuration it reads.

test_proxy.py and sse.test.js both cover the request path. These cover the part a
*different person on a different machine* actually depends on: that
terraform.tfvars.example declares everything Terraform will demand, that the
placeholders it ships are exactly the ones variables.tf refuses to deploy, that
app.js and the module rendering it agree on the template variables, and that
deploy.sh's own tfvars parser can read the example file.

None of this needs AWS, Docker or a deployment.
"""

import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]

VARIABLES_TF = (ROOT / "terraform" / "variables.tf").read_text()
TFVARS_EXAMPLE = (ROOT / "terraform" / "terraform.tfvars.example").read_text()
DEPLOY_SH = (ROOT / "scripts" / "deploy.sh").read_text()
DESTROY_SH = (ROOT / "scripts" / "destroy.sh").read_text()


def variable_blocks():
    """Map each variable name in variables.tf to its block text.

    Sliced between consecutive `variable "x" {` headers rather than by counting
    braces, so a brace inside a description or a validation regex cannot confuse it.
    """
    starts = [
        (m.group(1), m.start())
        for m in re.finditer(r'variable\s+"([^"]+)"\s*\{', VARIABLES_TF)
    ]
    assert starts, "no variable blocks found in variables.tf"

    return {
        name: VARIABLES_TF[pos: starts[i + 1][1] if i + 1 < len(starts) else len(VARIABLES_TF)]
        for i, (name, pos) in enumerate(starts)
    }


def example_value(name):
    match = re.search(r'^\s*%s\s*=\s*"([^"]*)"' % re.escape(name), TFVARS_EXAMPLE, re.M)
    return match.group(1) if match else None


def test_example_tfvars_declares_every_variable_without_a_default():
    """A variable with no default is one Terraform will stop and ask for."""
    required = [
        name
        for name, block in variable_blocks().items()
        if not re.search(r"^\s*default\s*=", block, re.M)
    ]

    assert required, "expected at least one required variable"

    missing = [name for name in required if example_value(name) is None]

    assert not missing, (
        "terraform.tfvars.example is missing required variable(s): "
        + ", ".join(missing)
        + ". A clean clone would fail with 'No value for required variable'."
    )


def test_shipped_placeholder_keys_are_rejected_by_their_own_validation():
    """The example's placeholders must match the pattern variables.tf refuses.

    These two live in different files; if either is edited without the other, the
    project either ships a placeholder it happily deploys or a validation that
    rejects its own example.
    """
    blocks = variable_blocks()

    for name in ("public_api_key", "internal_api_key"):
        pattern = re.search(r'regex\("\(\?i\)([^"]+)"', blocks[name])
        assert pattern, f"{name} has no placeholder-rejecting validation"

        value = example_value(name)
        assert value, f"{name} is missing from terraform.tfvars.example"

        assert re.search(pattern.group(1), value, re.I), (
            f"the {name} placeholder in terraform.tfvars.example would pass "
            f"validation and deploy as a real key"
        )


def test_app_js_template_variables_match_what_the_module_supplies():
    """templatefile() fails on a missing variable and ignores a surplus one."""
    app_js = (ROOT / "frontend" / "app.js").read_text()
    module = (ROOT / "terraform" / "modules" / "frontend" / "main.tf").read_text()

    used = set(re.findall(r"\$\{([a-z_]+)\}", app_js))

    call = re.search(r"templatefile\([^,]+,\s*\{(.*?)\}\)", module, re.S)
    assert call, "could not find the templatefile() call in the frontend module"
    supplied = set(re.findall(r"^\s*([a-z_]+)\s*=", call.group(1), re.M))

    assert used == supplied, (
        f"app.js uses {sorted(used)} but the module supplies {sorted(supplied)}"
    )


def test_template_values_are_json_encoded():
    """app.js declares these bare, so Terraform has to emit the quoting.

    Without jsonencode(), a system_prompt containing a double quote renders an
    app.js that throws SyntaxError — the page loads but nothing works at all.
    """
    app_js = (ROOT / "frontend" / "app.js").read_text()
    module = (ROOT / "terraform" / "modules" / "frontend" / "main.tf").read_text()

    for name in ("alb_url", "system_prompt"):
        assert re.search(r"=\s*\$\{%s\};" % name, app_js), (
            f"{name} must be interpolated unquoted in app.js"
        )
        assert re.search(r"^\s*%s\s*=\s*jsonencode\(" % name, module, re.M), (
            f"{name} must be passed through jsonencode() in the frontend module"
        )


@pytest.mark.skipif(shutil.which("bash") is None, reason="bash not available")
def test_deploy_scripts_tfvars_parser_reads_the_example():
    """deploy.sh derives the state bucket name with this function before Terraform
    ever runs, so a parsing slip would create a bucket under the wrong name."""
    function = re.search(r"^tfvar\(\) \{.*?^\}", DEPLOY_SH, re.M | re.S)
    assert function, "could not find the tfvar() function in deploy.sh"

    script = "\n".join([
        "set -euo pipefail",
        'TFVARS="%s"' % (ROOT / "terraform" / "terraform.tfvars.example"),
        function.group(0),
        'echo "$(tfvar project_name FALLBACK)|$(tfvar aws_region FALLBACK)|'
        '$(tfvar not_a_real_setting FALLBACK)"',
    ])

    out = subprocess.run(
        ["bash", "-c", script], capture_output=True, text=True, check=True
    ).stdout.strip()

    assert out == "gemma-inference|eu-central-1|FALLBACK", out


def test_both_scripts_support_unattended_runs():
    """The README documents AUTO_APPROVE=1; without it a piped or CI run of these
    scripts dies at `read` with exit 1 and no message at all."""
    for name, source in (("deploy.sh", DEPLOY_SH), ("destroy.sh", DESTROY_SH)):
        assert "AUTO_APPROVE" in source, f"{name} has no unattended mode"
        assert re.search(r"read -r -p", source), (
            f"{name} must use `read -r -p ... || ...` so end-of-input cannot "
            f"abort the script silently under set -e"
        )
