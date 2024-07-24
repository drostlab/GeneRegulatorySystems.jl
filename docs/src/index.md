# GeneRegulatorySystems.jl

This software constructs and orchestrates the simulation of single-cell gene regulatory models.

## Overview

The package contains components to construct complex models of single-cell gene regulation from templates and can coordinate reproducible simulation through a flexible scheduling mechanism and output format. The core regulation models are currently defined using [Catalyst.jl](https://github.com/SciML/Catalyst.jl) and simulated via [JumpProcesses.jl](https://github.com/SciML/JumpProcesses.jl), allowing them to be treated in isolation with various tools from the SciML ecosystem. Scheduling supports various forms of instant adjustment and fine-grained output control.

Features include:

* Construction of Catalyst.jl `ReactionSystem`-based gene regulation models using a simple JSON-based template language.
* Simulation using exact stochastic methods from JumpProcesses.jl.
* Experiment scheduling mechanism that supports complex observation models, seed control and simulation branching, as well as persistent and transient interventions (including periodic interventions).
* Export to counts matrices for downstream applications.

## Usage

The package can be used either as a standalone application or as a library.

* The primary use case is to use the included command line tools to run prepared simulation experiments and potentially to export the results to (wide-format) molecular counts data. See [Getting started](@ref) for instructions and [Results format](@ref) for a description of the native on-disk format.

* The advanced use case is to import and use this package in a Julia session to access the produced (mostly SciML-based) models, either because more control over the simulation is required or to enable static analysis. This is described in [Usage as a library](@ref).

Both variants require a working installation of Julia ≥ v1.10.
This package is currently not registered.
