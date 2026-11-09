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
    if (!Arrays.asList("fixture.md", "fixture.pdf", "oversize.txt", "unsupported.docx", "denied.txt").contains(name)) throw new FileNotFoundException();
    return new File(getContext().getCacheDir(), name);
  }
  @Override public boolean onCreate() {
    try {
      for (String name : new String[]{"fixture.md", "fixture.pdf"}) {
        try (InputStream in = getContext().getAssets().open(name); OutputStream out = new FileOutputStream(new File(getContext().getCacheDir(),name))) { byte[] b=new byte[8192]; int n; while((n=in.read(b))!=-1)out.write(b,0,n); }
      }
      try(OutputStream out=new FileOutputStream(new File(getContext().getCacheDir(),"oversize.txt"))){out.write(new byte[2*1024*1024+1]);}
      try(OutputStream out=new FileOutputStream(new File(getContext().getCacheDir(),"unsupported.docx"))){out.write(new byte[]{1,2,3});}
      try(OutputStream out=new FileOutputStream(new File(getContext().getCacheDir(),"denied.txt"))){out.write(new byte[]{65,66,67});}
      return true;
    } catch(IOException e) {throw new IllegalStateException(e);}
  }
  @Override public String getType(Uri uri) {
    String name=uri.getLastPathSegment();
    if("fixture.pdf".equals(name))return "application/pdf";
    if("fixture.md".equals(name))return "text/markdown";
    if("oversize.txt".equals(name)||"denied.txt".equals(name))return "text/plain";
    return "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
  }
  @Override public Cursor query(Uri uri,String[] projection,String selection,String[] args,String sort) {
    try {File file=source(uri);MatrixCursor c=new MatrixCursor(new String[]{"_display_name","_size"}); c.addRow(new Object[]{file.getName(),file.length()});return c;} catch(FileNotFoundException e){return null;}
  }
  @Override public ParcelFileDescriptor openFile(Uri uri,String mode) throws FileNotFoundException {
    if(!"r".equals(mode))throw new FileNotFoundException();
    return ParcelFileDescriptor.open(source(uri),ParcelFileDescriptor.MODE_READ_ONLY);
  }
  @Override public Uri insert(Uri uri,ContentValues values){throw new UnsupportedOperationException();}
  @Override public int delete(Uri uri,String where,String[] args){throw new UnsupportedOperationException();}
  @Override public int update(Uri uri,ContentValues values,String where,String[] args){throw new UnsupportedOperationException();}
}
