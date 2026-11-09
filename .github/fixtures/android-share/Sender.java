package dev.refract.sharefixture;
import android.app.Activity;
import android.os.Bundle;
import android.content.Intent;
import android.content.ClipData;
import android.net.Uri;
import java.util.ArrayList;

/** Test APK only. Uses real transient content-provider grants, not file:// or adb paths. */
public class Sender extends Activity {
  @Override public void onCreate(Bundle state) {
    super.onCreate(state);
    String mode = getIntent().getStringExtra("mode");
    Intent send = new Intent(Intent.ACTION_SEND);
    send.setComponent(new android.content.ComponentName("dev.refract", "dev.refract.MainActivity"));
    send.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
    if ("cold".equals(mode) || "warm".equals(mode)) {
      send.setType("text/plain"); send.putExtra(Intent.EXTRA_TEXT, "cold".equals(mode) ? "Cold start synthetic shared text" : "Warm synthetic share must not replace the open draft");
    } else if ("urlclip".equals(mode)) {
      send.setType("text/plain");
      send.setClipData(ClipData.newRawUri("Synthetic address", Uri.parse("https://example.invalid/not-fetched?source=fixture")));
    } else {
      String file = "denied".equals(mode) ? "denied.txt" : "oversize".equals(mode) ? "oversize.txt" : "unsupported".equals(mode) ? "unsupported.docx" : "fixture.md";
      Uri uri = Uri.parse("content://dev.refract.sharefixture.source/" + file);
      send.setType("text/plain");
      ClipData clips = ClipData.newRawUri("Synthetic shared source", uri);
      if ("multiple".equals(mode)) {
        send.setAction(Intent.ACTION_SEND_MULTIPLE); send.setType("*/*");
        ArrayList<Uri> uris = new ArrayList<>(); uris.add(uri);
        Uri pdf = Uri.parse("content://dev.refract.sharefixture.source/fixture.pdf"); uris.add(pdf); clips.addItem(new ClipData.Item(pdf));
        send.putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris);
      } else if (!"clip".equals(mode)) send.putExtra(Intent.EXTRA_STREAM, uri);
      send.setClipData(clips);
      if (!"denied".equals(mode)) send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
    }
    startActivity(send); finish();
  }
}
