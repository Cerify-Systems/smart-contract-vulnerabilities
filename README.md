# Smart Contract Vulnerabilities Archive

A centralized repository for tracking and analyzing smart contract vulnerability incidents. This repository contains the exact versions of vulnerable Solidity contracts, their dependencies, and related incident documentation.

## Repository Scope
* **Language:** Restricted to **Solidity** vulnerabilities only at this time.
* **Goal:** To build a comprehensive test suite and database of distinct vulnerabilities.

## Folder Structure & Naming Conventions

For every new incident, create a single root-level folder using the following naming convention:
`YYYY-MM-NAME` (Replace "NAME" with the protocol or project name that was exploited).

**Inside each `YYYY-MM-NAME` folder, you must include:**
1. **`/contracts/` directory:** Contains all relevant vulnerable `.sol` files. 
   * *Critical Requirement:* These files must be **self-contained**. All other imports and dependencies must be downloaded and available within this `contracts` folder.
2. **Incident Documentation:** Text-based files containing dumped content from blogs, Twitter threads, post-mortems, and general internet descriptions detailing the vulnerability.

## Workflow & Contribution Guidelines

1. **Claiming an Incident:** To avoid duplicate work, interns must use the designated Google Chat thread to inform the team which incident they are working on. Claims are on a First-Come, First-Served (FCFS) basis. Do not download or work on an incident that someone else has already claimed.
2. **Branching:** Do not commit directly to the `master` branch. Create a corresponding working branch for your incident(s).
3. **Pull Requests:** When your incident folder is complete, create a Pull Request against the `master` branch.
4. **Reviewers:** You **must** tag Saurabh Joshi (GitHub ID: `sbjoshi`) as a reviewer on your Pull Request.
