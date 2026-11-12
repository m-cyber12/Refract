package dev.refract.sharefixture;
import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import java.io.*;
import java.util.Arrays;

public class SourceProvider extends ContentProvider {
  private File source(Uri uri) throws FileNotFoundException {
    String name = uri.getLastPathSegment();
    if (!Arrays.asList("fixture.md", "fixture.pdf", "fixture.csv", "fixture.json", "oversize.txt", "unsupported.docx", "denied.txt", "mismatch.txt", "unknown.txt", "fallback.txt").contains(name)) throw new FileNotFoundException();
    return new File(getContext().getCacheDir(), name);
  }
  @Override public boolean onCreate() {
    try {
      for (String name : new String[]{"fixture.md", "fixture.pdf"}) {
        try (InputStream in = getContext().getAssets().open(name); OutputStream out = new FileOutputStream(new File(getContext().getCacheDir(),name))) { byte[] b=new byte[8192]; int n; while((n=in.read(b))!=-1)out.write(b,0,n); }
      }
      try(OutputStream out=new FileOutputStream(new File(getContext().getCacheDir(),"fixture.csv"))){out.write("\uFEFFname,value\r\nAlice,1\r\n".getBytes(java.nio.charset.StandardCharsets.UTF_8));}
      try(OutputStream out=new FileOutputStream(new File(getContext().getCacheDir(),"fixture.json"))){out.write("{\"fixture\":\"local-only-json\"}".getBytes(java.nio.charset.StandardCharsets.UTF_8));}
      try(OutputStream out=new FileOutputStream(new File(getContext().getCacheDir(),"oversize.txt"))){out.write(new byte[2*1024*1024+1]);}
      try(OutputStream out=new FileOutputStream(new File(getContext().getCacheDir(),"unsupported.docx"))){out.write(new byte[]{1,2,3});}
      for(String name:new String[]{"denied.txt","mismatch.txt","unknown.txt","fallback.txt"})try(OutputStream out=new FileOutputStream(new File(getContext().getCacheDir(),name))){out.write(new byte[]{65,66,67});}
      return true;
    } catch(IOException e) {throw new IllegalStateException(e);}
  }
  @Override public String getType(Uri uri) {
    String name=uri.getLastPathSegment();
    if("fixture.pdf".equals(name))return "application/pdf";
    if("fixture.md".equals(name))return "text/markdown";
    if("fixture.csv".equals(name))return "text/csv";
    if("fixture.json".equals(name))return "application/json";
    if("oversize.txt".equals(name)||"denied.txt".equals(name)||"mismatch.txt".equals(name)||"unknown.txt".equals(name)||"fallback.txt".equals(name))return "text/plain";
    return "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
  }
  @Override public Cursor query(Uri uri,String[] projection,String selection,String[] args,String sort) {
    if ("fallback.txt".equals(uri.getLastPathSegment()) && projection != null && Arrays.asList(projection).contains("_size")) throw new IllegalArgumentException("size unsupported");
    try {File file=source(uri);MatrixCursor c=new MatrixCursor(new String[]{"_display_name","_size"}); c.addRow(new Object[]{file.getName(),"mismatch.txt".equals(file.getName()) ? file.length()+1 : "unknown.txt".equals(file.getName()) ? null : file.length()});return c;} catch(FileNotFoundException e){return null;}
  }
  @Override public ParcelFileDescriptor openFile(Uri uri,String mode) throws FileNotFoundException {
    if(!"r".equals(mode))throw new FileNotFoundException();
    return ParcelFileDescriptor.open(source(uri),ParcelFileDescriptor.MODE_READ_ONLY);
  }
  @Override public Uri insert(Uri uri,ContentValues values){throw new UnsupportedOperationException();}
  @Override public int delete(Uri uri,String where,String[] args){throw new UnsupportedOperationException();}
  @Override public int update(Uri uri,ContentValues values,String where,String[] args){throw new UnsupportedOperationException();}
}
