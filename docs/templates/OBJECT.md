# `ObjectApiName__c` (Object Label)

<!-- Copy to docs/objects/<ObjectApiName>.md. Use for custom objects. Delete any section that does not apply. -->

| Reviewed by | Date | Checklist step | Package version |
| ----------- | ---- | -------------- | --------------- |
|             |      | 1.x.x          |                 |

## Purpose

One or two sentences. What one record represents, who creates it, and when.

## At a glance

| Property             | Value                                            |
| -------------------- | ------------------------------------------------ |
| Kind                 | Configuration, junction, runtime, audit evidence |
| Sharing (internal)   |                                                  |
| Sharing (external)   |                                                  |
| Name field           | Text or auto-number, and the format              |
| Field history        | On or off, and which fields                      |
| Created by           | Admin, user, or Apex (which class)               |
| Typical volume       | Records per org, or per message                  |
| Retention            | How and when records are deleted                 |
| Deleted with package | What a subscriber keeps on uninstall             |

## Relationships

| Field | Type | To  | On delete of the parent | Why |
| ----- | ---- | --- | ----------------------- | --- |
|       |      |     |                         |     |

Where this object sits in the model: see [ERD.md](ERD.md).

## Fields

| Field | Type | Required | Set by | Read by | Purpose |
| ----- | ---- | -------- | ------ | ------- | ------- |
|       |      |          |        |         |         |

Picklist values, where they carry meaning:

| Field | Value | Meaning |
| ----- | ----- | ------- |
|       |       |         |

## Rules enforced on save

### Validation rules

| Rule | Refuses | Message shown |
| ---- | ------- | ------------- |
|      |         |               |

### Trigger and handler

| Trigger | Events | Handler | Test |
| ------- | ------ | ------- | ---- |
|         |        |         |      |

What the handler does, one line per behaviour:

- Before insert:
- Before update:
- After insert:
- After update:

What happens if a check cannot run (fail closed or open):

## Access

| Permission set    | Read | Create | Edit | Delete | Notes on field access |
| ----------------- | ---- | ------ | ---- | ------ | --------------------- |
| AIAssistUser      |      |        |      |        |                       |
| AIAssistSuperUser |      |        |      |        |                       |
| AIAssistAdminUser |      |        |      |        |                       |

## Where it is used

| Apex class | Reads | Writes | Why |
| ---------- | ----- | ------ | --- |
|            |       |        |     |

## Presentation

| Item           | Name | Notes |
| -------------- | ---- | ----- |
| Tab            |      |       |
| Page layout    |      |       |
| Compact layout |      |       |
| List views     |      |       |

## Managed package permanence

What cannot change once this object is in a released version, and anything decided now because of that.

## Open questions and follow-ups

- [ ]
