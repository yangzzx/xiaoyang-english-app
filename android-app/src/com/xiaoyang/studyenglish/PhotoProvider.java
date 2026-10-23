package com.xiaoyang.studyenglish;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;
import java.io.File;
import java.io.FileNotFoundException;

/** Only the temporary camera photo can be shared; app data is never exposed. */
public final class PhotoProvider extends ContentProvider {
    private File photo(Uri uri) throws FileNotFoundException {
        if (!"com.xiaoyang.studyenglish.photos".equals(uri.getAuthority()) || !"/note-photo.jpg".equals(uri.getPath()))
            throw new FileNotFoundException("Unknown photo");
        return new File(getContext().getFilesDir(), "note-photo.jpg");
    }
    @Override public boolean onCreate() { return true; }
    @Override public String getType(Uri uri) { return "image/jpeg"; }
    @Override public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        return ParcelFileDescriptor.open(photo(uri), ParcelFileDescriptor.parseMode(mode));
    }
    @Override public Cursor query(Uri uri, String[] projection, String selection, String[] args, String order) {
        try {
            File file = photo(uri);
            String[] cols = projection == null ? new String[]{OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE} : projection;
            MatrixCursor cursor = new MatrixCursor(cols); Object[] row = new Object[cols.length];
            for (int i = 0; i < cols.length; i++) row[i] = OpenableColumns.DISPLAY_NAME.equals(cols[i]) ? "note-photo.jpg" : OpenableColumns.SIZE.equals(cols[i]) ? file.length() : null;
            cursor.addRow(row); return cursor;
        } catch (FileNotFoundException e) { return null; }
    }
    @Override public Uri insert(Uri u, ContentValues v) { throw new UnsupportedOperationException(); }
    @Override public int update(Uri u, ContentValues v, String s, String[] a) { throw new UnsupportedOperationException(); }
    @Override public int delete(Uri u, String s, String[] a) { throw new UnsupportedOperationException(); }
}
