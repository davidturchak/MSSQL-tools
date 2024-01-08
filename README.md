# SQL-install-restore-db.ps1

## Introduction

This PowerShell script is designed to facilitate the creation or restoration of a SQL Server database. It includes functions for installing SQL Server, restoring a database from a backup file, and checking the installation status.

## Prerequisites

- PowerShell 5.1 or later
- Internet access to SQL Server 2019 ISO: [Download SQL Server 2019 ISO](https://download.microsoft.com/download/7/c/1/7c14e92e-bdcb-4f89-b7cf-93543e7112d1/SQLServer2019-x64-ENU-Dev.iso)
- Internet access to SQL Server Management Studio (SSMS) setup: [Download SSMS](https://aka.ms/ssmsfullsetup)
- Ensure BITS (Background Intelligent Transfer Service) is available

## Usage

```powershell
.\Create-SqlDatabase.ps1 -databaseName <DatabaseName> [-dataFilePath <DataFilePath>] [-logFilePath <LogFilePath>] [-backupFilePath <BackupFilePath>]

# Parameters

- `databaseName`: The name of the database to create or restore (required).
- `dataFilePath`: Path for the data file (default: `C:\Program Files\Microsoft SQL Server\MSSQL15.SQLEXPRESS\MSSQL\DATA\`).
- `logFilePath`: Path for the log file (default: `C:\Program Files\Microsoft SQL Server\MSSQL15.SQLEXPRESS\MSSQL\DATA\`).
- `backupFilePath`: Path to the backup file for restore (required for restore).
