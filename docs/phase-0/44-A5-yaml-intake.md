# YAML intake as plain text

YAML and YML file selections can be reviewed as strict UTF-8 plain text, not
as parsed YAML. Preview and save remain separate, with the existing 2 MiB bound.
Unedited text preserves a UTF-8 BOM and line endings; editing makes the edited
text the captured original. The file name is not stored as format metadata.
YAML can contain secrets: the review screen warns that values are not redacted,
validated, executed or fetched. No YAML parser or tag interpreter is introduced.

Android share intake accepts the filename extensions and common YAML MIME types;
iOS accepts supported file URLs or plain-text representations. Synthetic widget,
provider and Android emulator tests cover selected paths, not all providers or
physical devices. OS/provider caches and their own type handling remain outside
the app's control. This does not promise universal format support.
