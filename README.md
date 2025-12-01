# Zscaler Adaptive Access Engine

This repository contains a collection of integration components designed to work with the Zscaler platform, enabling adaptive access control based on security signals from various sources.

## Connectors

### Zscaler & Microsoft Defender Integration Connector

This connector deploys an Azure Logic App that periodically retrieves device security posture data from the Microsoft Defender for Endpoint API and sends it to an Azure Event Hub. This enables Zscaler to consume device state information and enforce adaptive access policies.

The entire infrastructure is defined as an Azure Bicep template.

**Features:**
- Periodically fetches device data from Microsoft Defender.
- Uses Azure Key Vault for secure credential storage.
- Publishes data to a secure Azure Event Hub.
- The trigger frequency is configurable.

For detailed information on architecture, deployment, and configuration, please see the [Zscaler & Microsoft Defender Integration Connector README](./zscaler-defender-conector/README.md).