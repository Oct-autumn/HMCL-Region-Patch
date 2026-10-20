package io.github.octautumn.hmclpatch;

import java.io.IOException;
import java.io.PrintStream;
import java.net.URISyntaxException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;

/**
 * 极简日志工具。
 * <p>
 * premain 阶段 HMCL 自己的日志系统（org.jackhuang.hmcl.util.logging.Logger）还没有初始化，
 * 所以注入包不能依赖它，只能自己往 stderr 和文件里写。
 * <p>
 * 官方 Windows exe 用 javaw.exe 启动，stderr 没有控制台，日志文件是唯一的观察窗口。
 */
public final class PatchLogger {

    private static final DateTimeFormatter TIMESTAMP = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS");

    private static final String LOG_FILE_NAME = "hmcl-region-patch.log";

    /** 是否输出调试级别的日志（-javaagent:xxx.jar=verbose 时开启）。 */
    private static volatile boolean verbose;

    /** 日志文件路径；为 null 表示文件不可用，只写 stderr。 */
    private static volatile Path logFile;

    private static final PrintStream CONSOLE = System.err;

    private PatchLogger() {
    }

    /**
     * 在 premain 里初始化日志。
     *
     * @param agentArgs -javaagent 参数（等号后面的部分），可包含 verbose
     */
    public static void init(String agentArgs) {
        verbose = agentArgs != null && agentArgs.toLowerCase().contains("verbose");
        logFile = locateLogFile();
        if (logFile != null) {
            // 每次启动覆盖写入，避免日志无限增长；本次启动的注入结果就是最重要的信息
            try {
                Files.writeString(logFile, "", StandardCharsets.UTF_8);
                logFile.toFile().setWritable(true);
            } catch (IOException e) {
                logFile = null;
            }
        }
    }

    /**
     * 定位日志文件：优先放在 agent jar 所在目录，失败则退到当前工作目录。
     */
    private static Path locateLogFile() {
        try {
            var source = PatchLogger.class.getProtectionDomain().getCodeSource();
            if (source != null && source.getLocation() != null) {
                Path location = Paths.get(source.getLocation().toURI());
                Path dir = Files.isDirectory(location) ? location : location.getParent();
                if (dir != null) {
                    return dir.resolve(LOG_FILE_NAME);
                }
            }
        } catch (URISyntaxException | RuntimeException ignored) {
            // 定位失败就走下面的兜底
        }
        try {
            return Paths.get(System.getProperty("user.dir", ".")).resolve(LOG_FILE_NAME);
        } catch (RuntimeException e) {
            return null;
        }
    }

    public static void info(String message) {
        write("INFO", message, null);
    }

    public static void warn(String message) {
        write("WARN", message, null);
    }

    public static void error(String message, Throwable throwable) {
        write("ERROR", message, throwable);
    }

    public static void debug(String message) {
        if (verbose) {
            write("DEBUG", message, null);
        }
    }

    private static synchronized void write(String level, String message, Throwable throwable) {
        String line = "[" + LocalDateTime.now().format(TIMESTAMP) + "] [" + level + "] " + message;
        CONSOLE.println(line);
        if (throwable != null) {
            throwable.printStackTrace(CONSOLE);
        }
        Path file = logFile;
        if (file == null) {
            return;
        }
        StringBuilder content = new StringBuilder(line).append(System.lineSeparator());
        if (throwable != null) {
            var buffer = new java.io.StringWriter();
            throwable.printStackTrace(new java.io.PrintWriter(buffer));
            content.append(buffer).append(System.lineSeparator());
        }
        try {
            Files.writeString(file, content, StandardCharsets.UTF_8,
                    java.nio.file.StandardOpenOption.CREATE, java.nio.file.StandardOpenOption.APPEND);
        } catch (IOException e) {
            // 文件写不了就只保留 stderr，不因为日志问题影响 HMCL 启动
            logFile = null;
        }
    }
}
