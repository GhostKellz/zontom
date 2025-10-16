# ZonTOM CLI Guide

Command-line tool for parsing and validating TOML files.

## Installation

```bash
# Build and install
zig build install --prefix ~/.local

# Or run directly
zig build run -- parse example.toml
```

## Commands

### `parse`

Parse and display TOML file structure.

```bash
zontom parse <file> [--verbose|-v]
```

**Options:**
- `-v`, `--verbose` - Enable verbose logging with debug information

**Example:**
```bash
$ zontom parse config.toml

=== TOML Parse Summary ===
File: config.toml
Size: 245 bytes
Root entries: 3

Root keys:
  ├─ package: table
  ├─ dependencies: table
  ├─ build: table

✓ Validation successful!
```

**Verbose mode:**
```bash
$ zontom parse config.toml -v

[1760642590] [INFO] Parsing TOML file: config.toml
[1760642590] [DEBUG] File size: 245 bytes
[1760642590] [INFO] Successfully parsed TOML file
[1760642590] [INFO] Root table contains 3 entries

=== TOML Parse Summary ===
...
```

### `validate`

Validate TOML file syntax without displaying contents.

```bash
zontom validate <file> [--quiet|-q]
```

**Options:**
- `-q`, `--quiet` - Suppress output on success (useful for scripts)

**Example:**
```bash
$ zontom validate config.toml
✓ config.toml is valid TOML

$ zontom validate invalid.toml

❌ Validation Failed

Error at line 5, column 12:
  key value
      ^
  Expected '=' after key
  Hint: Did you mean to use a dot '.' for a nested key?
```

**Quiet mode:**
```bash
$ zontom validate config.toml -q
$ echo $?
0

$ zontom validate invalid.toml -q
$ echo $?
1
```

### `fmt` (Coming Soon)

Format a TOML file with consistent style.

```bash
zontom fmt <file>
```

**Status:** Not yet implemented in v0.1.0

## Error Messages

ZonTOM provides detailed, actionable error messages:

```bash
$ zontom validate broken.toml

❌ Validation Failed

Error at line 12, column 5:
  = invalid
  ^
  Expected key
  Hint: Did you forget to add a key before the '='?
```

Error messages include:
- **Line and column** numbers
- **Source line context** showing the problematic code
- **Caret indicator** pointing to the exact error location
- **Clear message** explaining what went wrong
- **Helpful hints** suggesting how to fix the issue

## Exit Codes

- `0` - Success
- `1` - Parse/validation error
- Other - System or IO error

## Integration with Other Tools

### CI/CD Pipeline

```yaml
# .github/workflows/validate.yml
name: Validate TOML
on: [push, pull_request]
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Setup Zig
        uses: goto-bus-stop/setup-zig@v2
      - name: Install ZonTOM
        run: |
          git clone https://github.com/user/zontom
          cd zontom
          zig build install --prefix ~/.local
      - name: Validate configs
        run: |
          find . -name "*.toml" -exec zontom validate {} \\;
```

### Pre-commit Hook

```bash
#!/bin/bash
# .git/hooks/pre-commit

for file in $(git diff --cached --name-only --diff-filter=ACM | grep '\\.toml$'); do
    zontom validate "$file" -q
    if [ $? -ne 0 ]; then
        echo "TOML validation failed for $file"
        exit 1
    fi
done
```

### Shell Script

```bash
#!/bin/bash
# validate-all-toml.sh

failed=0
for file in **/*.toml; do
    if ! zontom validate "$file" -q; then
        echo "❌ $file"
        failed=1
    else
        echo "✓ $file"
    fi
done

exit $failed
```

### Makefile

```makefile
.PHONY: validate-toml
validate-toml:
\t@find . -name "*.toml" | while read file; do \\
\t\tzontom validate "$$file" -q || exit 1; \\
\tdone
\t@echo "All TOML files are valid"
```

## Tips and Tricks

### Batch Validation

```bash
# Validate all TOML files in current directory
find . -name "*.toml" -exec zontom validate {} -q \\; && echo "All valid!"

# Validate specific files
zontom validate config.toml database.toml app.toml
```

### Parse with Grep

```bash
# Check if a specific key exists
zontom parse config.toml | grep "debug:"

# Count root keys
zontom parse config.toml | grep "├─" | wc -l
```

### Using in Scripts

```bash
#!/bin/bash

# Validate before deploying
if zontom validate production.toml -q; then
    echo "Config valid, deploying..."
    kubectl apply -f deployment.yaml
else
    echo "Invalid config, aborting"
    exit 1
fi
```

## Common Use Cases

### Development Workflow

```bash
# Check syntax while editing
watch -n 1 zontom validate config.toml -q

# Parse to see structure
zontom parse config.toml | less
```

### Debugging

```bash
# Verbose output for troubleshooting
zontom parse broken.toml -v 2>&1 | tee debug.log

# Check specific file
zontom validate suspect.toml
```

### Quality Assurance

```bash
# Validate all configs before commit
git diff --name-only --cached | grep '\\.toml$' | xargs -I {} zontom validate {} -q
```

## See Also

- [API Reference](API.md) - Library usage
- [Examples](EXAMPLES.md) - Code examples
