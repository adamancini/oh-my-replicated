# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains custom Oh My Zsh plugins maintained by Replicated engineers. It's a collection of shell utilities that integrate with Google Cloud Platform for managing compute instances, focused primarily on the `replicated-gcommands` plugin.

## Repository Structure

- `replicated-gcommands.plugin.zsh` - Main plugin containing GCP instance management functions
- `README.md` - Installation instructions and plugin documentation
- `.specstory/` - SpecStory extension artifacts (AI chat history preservation)

## Core Plugin Architecture

The `replicated-gcommands.plugin.zsh` implements a suite of GCP management functions that:

- Require `gcloud` CLI to be installed and configured
- Use `GUSER` environment variable to filter instances by ownership
- Optionally use `GPREFIX` environment variable to prefix instance names
- Display current gcloud configuration context for all operations

### Key Functions

**Instance Management:**
- `gcreate` - Create GCP instances with standardized configuration (labels, disk sizes, service accounts)
- `glist` - List instances owned by current user
- `gstart`/`gstop` - Start/stop instances by name prefix
- `gdelete` - Delete instances and associated disks
- `gssh` - SSH to instances with auto-retry logic
- `gssh-forward` - SSH with port forwarding (8800, 8888)

**Network Management:**
- `gonline` - Add external IP access to instances
- `gairgap` - Remove external IP access (air-gap instances)

**Storage Management:**
- `gdisk` - Create persistent disks
- `gattach` - Attach disks to instances

**Utility Functions:**
- `genv` - Display current gcloud configuration
- `getdate` - Cross-platform date calculation for instance expiration
- `gtag` - Add network tags to instances

## Plugin Installation

The plugin follows Oh My Zsh conventions and can be installed via:

1. Manual installation to `~/.oh-my-zsh/custom/plugins/`
2. Package managers like Antigen: `antigen bundle replicatedhq/oh-my-replicated@main`

## Required Configuration

Users must configure these environment variables:
```zsh
GUSER='username'      # Required: matches email username for instance filtering
GPREFIX='username'    # Optional: prefixes instance names
```

## Development Notes

- No formal build/test/lint processes - this is a shell script collection
- Functions use consistent error handling patterns with usage messages
- Cross-platform compatibility for macOS (Darwin) and Linux date commands
- Defensive scripting with parameter validation and gcloud CLI availability checks
- Instance operations are scoped to user ownership via labels.owner filtering