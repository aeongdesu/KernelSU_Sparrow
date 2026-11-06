import android.net.Uri;
import android.os.IBinder;
import java.lang.reflect.Method;

public final class Notify { // Pokes PicoSystemConfig's whitelist ContentObserver
    public static void main(String[] args) throws Exception {
        String uri = args.length > 0 ? args[0] : "content://com.pico.settings/whitelist";
        Class<?> sm = Class.forName("android.os.ServiceManager");
        IBinder binder = (IBinder) sm.getMethod("getService", String.class).invoke(null, "content");
        if (binder == null) throw new IllegalStateException("content service not found");
        Class<?> stub = Class.forName("android.content.IContentService$Stub");
        Object service = stub.getMethod("asInterface", IBinder.class).invoke(null, binder);
        Class<?> observer = Class.forName("android.database.IContentObserver");
        Method m = service.getClass().getMethod("notifyChange", Uri[].class, observer, boolean.class, int.class, int.class, int.class, String.class);
        m.invoke(service, new Uri[]{Uri.parse(uri)}, null, false, 0, 0, 25, "root");
        System.out.println("notified " + uri);
    }
}
