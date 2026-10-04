PACKAGE REVIEW CHECKLIST
========================

A complete, ordered review of everything in the AI Assist managed package (force-app/main/default). Every metadata file in the package appears on exactly one of the three checklists below: 1,074 files as of 2026-10-04.


HOW TO USE IT
-------------

1. Work through the three parts in order. Do not start a part until the one before it is signed off.
2. Inside a part, work top to bottom. The order is by dependency, so nothing you review depends on something you have not reviewed yet.
3. Tick a box ([x]) when the item passes the checks under "What to check" below. If it does not pass, leave it unticked and add a note on the line beneath it.
4. When an object or feature is finished, fill in its page from docs/templates/ and tick its "Documented" box.

Part  File                        Covers                                                                                                                                     Boxes
----  --------------------------  -----------------------------------------------------------------------------------------------------------------------------------------  -----
1     01_OBJECT_MODEL.txt         Global value sets, objects, fields, validation rules, list views, layouts, tabs, indexes, triggers, trigger handlers and their tests       773
2     02_APEX.txt                 Every other Apex class and its test, by feature, plus feature parameters                                                                   199
3     03_ACCESS_UI_PACKAGING.txt  Custom permissions, permission sets, sharing, custom labels, notification type, assets, project files, CI, existing docs, what is missing  244


WHY THIS ORDER
--------------

Object model first. Apex, permission sets and layouts all refer to objects and fields. A field renamed late forces every one of them to be reviewed again. In a managed package it matters more: once a version is released, an object or field cannot be deleted or have its API name or type changed.

Triggers and handlers with their object. A handler is the part of the object model that validation rules cannot express. Reviewing it beside the fields and rules shows the whole of what is enforced on save in one place.

Apex from the lowest layer up. Constants and utilities, then logging, then data access, then limits and licensing, then the features, then the orchestration that calls all of them, then the chat API on top. A class is reviewed only after everything it calls.

Access last. A permission set cannot be judged until you know what each thing it grants does.


PART 1 ORDER: OBJECT MODEL
--------------------------

A parent is always above the objects that look up to it.

Step    Object                      Kind                  Fields  Rules  Trigger
------  --------------------------  --------------------  ------  -----  -------
1.2.1   AIModelConfiguration__c     Object                15      8      Yes
1.2.2   AIAgent__c                  Object                19      2      Yes
1.2.3   AIPromptTemplate__c         Object                11      2      Yes
1.2.4   AIDataSource__c             Object                12      5      Yes
1.2.5   AIWorkflowAction__c         Object                13      7      Yes
1.2.6   AIViolationRule__c          Object                12      3      Yes
1.3.1   AIAgentObject__c            Object                4       0      Yes
1.3.2   AIAgentDataSource__c        Object                4       0      Yes
1.3.3   AIAgentWorkflowAction__c    Object                4       0      Yes
1.3.4   AIAgentViolationRule__c     Object                4       0      Yes
1.3.5   AIAgentAssignment__c        Object                6       2      Yes
1.4.1   AIUsagePolicy__c            Object                14      1      Yes
1.4.2   AIUsagePolicyAssignment__c  Object                6       2      Yes
1.4.3   AIUserSettings__c           Object                12      1      Yes
1.4.4   AITermsAcknowledgment__c    Object                5       3      No
1.5.1   AIConversation__c           Object                15      1      Yes
1.5.2   AIConversationMessage__c    Object                16      0      Yes
1.5.3   AIExecutionStep__c          Object                27      3      No
1.5.4   AIFeedback__c               Object                5       1      No
1.5.5   AIViolation__c              Object                11      1      Yes
1.5.6   AIUsageDaily__c             Object                13      0      No
1.6.1   AIPIIRegistry__c            Object                8       2      No
1.6.2   AIPIIFieldMetadata__c       Object                9       0      No
1.6.3   AIPIIMapping__c             Object                2       0      No
1.6.4   AIPIIMaskingRecord__c       Object                8       1      No
1.7.1   AIDataDeletionRequest__c    Object                19      7      Yes
1.7.2   AIPlatformLog__c            Object                10      0      No
1.8.1   AIPlatformLogEvent__e       Platform event        10      0      Yes
1.8.2   AIMessageReadyEvent__e      Platform event        4       0      No
1.8.3   AIAgentProgressEvent__e     Platform event        3       0      No
1.8.4   AIViolationEvent__e         Platform event        8       0      No
1.9.1   AIPiiComplianceGroup__mdt   Custom metadata type  2       0      No
1.9.2   AIPiiDataMaskingRule__mdt   Custom metadata type  6       0      No
1.9.3   AIPiiFieldType__mdt         Custom metadata type  8       0      No
1.9.4   AIChatCommand__mdt          Custom metadata type  8       0      No
1.10.1  AIAssistSettings__c         Custom setting        44      0      No
1.10.2  AIAssistUISettings__c       Custom setting        10      0      No


PART 2 ORDER: APEX BY FEATURE
-----------------------------

Step  Feature                                 Classes (without tests)
----  --------------------------------------  -----------------------
2.1   Foundation and utilities                8
2.2   Logging                                 1
2.3   Data access                             2
2.4   Usage limits                            5
2.5   Plan and licence                        4
2.6   Providers and credentials               10
2.7   Privacy and PII                         6
2.8   Data sources                            6
2.9   Workflow actions                        5
2.10  Guardrails and violations               2
2.11  Agent orchestration                     1
2.12  Messaging pipeline                      10
2.13  Chat API                                10
2.14  Retention, deletion and scheduled jobs  6
2.15  Set-up and administration controllers   6
2.16  Install                                 1


WHAT TO CHECK
-------------

Object
~~~~~~

- Label, plural label and description say what a record is, in plain words.
- Sharing model, internal and external, matches docs/SECURITY_MODEL.md.
- Name field type (text or auto-number) and display format.
- Field history, activities, reports, search: on only where used.
- Deployment status is Deployed.

Field
~~~~~

- API name follows the naming rules (scripts/ci/check-naming.js); label is plain.
- Type, length, precision and scale are right, and final: they cannot change after release.
- Description and help text are filled in.
- Required, unique, external ID and default value are deliberate.
- Picklist: values, default, restricted or not, global value set or local.
- Relationship: lookup or master-detail, delete behaviour, relationship name, lookup filter.
- Something reads it and something writes it. A field nothing uses is removed now, before release.
- Access in each of the three permission sets.

Validation rule
~~~~~~~~~~~~~~~

- The formula does what its name says, including for blank values.
- The error message tells the user what to do, and sits on the right field.
- It does not block the package's own writes (batches, the install handler, tests).

Trigger and handler
~~~~~~~~~~~~~~~~~~~

- The trigger contains no logic and calls one handler.
- Events are the minimum needed.
- Bulk safe: no query or DML inside a loop; works for 200 records.
- Fails closed: if a check cannot run, the save is refused.
- No recursion between handlers.
- The test covers insert, update, bulk and the refusal paths.

Apex class
~~~~~~~~~~

- Sharing declaration is deliberate. without sharing has a written reason.
- global only where a subscriber must call or implement it. A global signature is permanent.
- Object and field permissions are enforced on every read and write made for a user.
- No hard-coded Ids, URLs or secrets. User-facing text is in custom labels.
- Limits: queries, DML, callouts, heap and CPU are bounded for the largest expected input.
- Errors are logged through AIPlatformLogManager and are never swallowed.
- The test asserts behaviour, not only coverage, and runs as a user with the right permission set.

Custom metadata type and custom setting
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- Visibility (public or protected) is deliberate.
- Each field has a safe default.
- Which records ship with the package, and whether a subscriber may edit them.

Platform event
~~~~~~~~~~~~~~

- Publish behaviour (publish immediately or after commit) fits its use.
- Who publishes and who subscribes are both named.
- Volume against the org's event allowance.

Permission set
~~~~~~~~~~~~~~

- Least access that lets the role do its job.
- No Modify All or View All without a reason.
- Every Apex class a user's entry points need is granted, and no more.


GAPS FOUND WHILE BUILDING THIS CHECKLIST
----------------------------------------

These came out of the inventory. Each is also a box in the relevant part.

Gap                                                                                                                                                                             Where it is tracked
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------  --------------------
No page layout for AIAgentObject__c, AIAgentViolationRule__c, AIPIIMapping__c, AIUsagePolicy__c, AIUsagePolicyAssignment__c, AIChatCommand__mdt                                 Part 1, each object
No tab for the five agent junction objects, AIUsagePolicyAssignment__c and AIPIIMapping__c                                                                                      Part 1, each object
No custom metadata records in the package for any of the four __mdt types                                                                                                       Part 1, section 1.9
Three platform events have no Apex subscriber in the package: AIMessageReadyEvent__e, AIAgentProgressEvent__e, AIViolationEvent__e                                              Part 1, section 1.8
Classes with no test class of their own: AIChatDataStructure, AIConfigurationAccess, AICredentialGateway, AIOrgUsageTotalsBatch, the two response classes, the five interfaces  Part 2, each class
Mixed casing in names: AIPIIRegistry__c and AIPiiFieldType__mdt; ObjectAPIName__c and ObjectApiName__c                                                                          Part 1, last section
No Lightning components, app, flexipages, named credentials or reports in the package                                                                                           Part 3, section 3.10

A missing test class or subscriber is not necessarily a fault: an interface needs no test, and an event may be meant for the chat window. The box is there so each one is a decision, not an oversight.


KEEPING IT CURRENT
------------------

The checklists were built from the metadata on 2026-10-04. When a component is added, add its line to the right section in the same pull request. When one is removed, remove its line.
