package io.github.octautumn.hmclpatch;

import java.io.IOException;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.net.URL;
import java.net.URLClassLoader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

/**
 * 无第三方测试框架的自测程序（build.sh --test / build.ps1 -Test 会运行）。
 * <p>
 * 用 {@code javax.tools.JavaCompiler} 现场编译几种不同结构的 RegionUtils 源码，
 * 交给 {@link RegionUtilsTransformer#patch} 改写，再用自定义 ClassLoader 加载，
 * 反射检查字段和方法的返回值。
 * <p>
 * 覆盖场景：
 * <ol>
 *   <li>当前 HMCL 的结构（checkMachineIsChinaMainland 方法）；</li>
 *   <li>检测方法被改名（靠 &lt;clinit&gt; 策略兜底）；</li>
 *   <li>只剩 public 判断方法（靠策略 3 兜底）；</li>
 *   <li>目标类结构完全不同（应返回 null，不抛异常）；</li>
 *   <li>非目标类（应直接放行）。</li>
 * </ol>
 */
public final class SelfTest {

    private static int passed;
    private static int failed;

    public static void main(String[] args) throws Exception {
        RegionUtilsTransformer transformer = new RegionUtilsTransformer();

        // 场景 1：与当前 HMCL 一致的结构
        test("当前 HMCL 结构（checkMachineIsChinaMainland）", () -> {
            byte[] original = compile("""
                    package org.jackhuang.hmcl.util;

                    public final class RegionUtils {
                        private static final boolean IS_CHINA_MAINLAND_MACHINE = checkMachineIsChinaMainland();

                        private static boolean checkMachineIsChinaMainland() {
                            // 模拟时区/语言检测：这里固定返回 true 表示“判定为大陆”
                            return true;
                        }

                        public static boolean isIsChinaMainlandMachine() {
                            return IS_CHINA_MAINLAND_MACHINE;
                        }

                        public static boolean isIsChinaMainlandNetwork() {
                            return IS_CHINA_MAINLAND_MACHINE;
                        }
                    }
                    """);
            byte[] patched = transformer.transform(null, RegionUtilsTransformer.TARGET_CLASS, null, null, original);
            assertNotNull(patched, "应改写字节码");
            Class<?> clazz = load(patched);
            assertFalse(invokeBoolean(clazz, "isIsChinaMainlandMachine"), "isIsChinaMainlandMachine()");
            assertFalse(invokeBoolean(clazz, "isIsChinaMainlandNetwork"), "isIsChinaMainlandNetwork()");
            assertFalse(readField(clazz, "IS_CHINA_MAINLAND_MACHINE"), "IS_CHINA_MAINLAND_MACHINE");
        });

        // 场景 2：检测方法被改名，策略 1 不命中，应由 <clinit> 策略兜底
        test("检测方法改名（<clinit> 策略兜底）", () -> {
            byte[] original = compile("""
                    package org.jackhuang.hmcl.util;

                    public final class RegionUtils {
                        private static final boolean IS_CHINA_MAINLAND_MACHINE = detect();

                        private static boolean detect() {
                            return true;
                        }

                        public static boolean isIsChinaMainlandMachine() {
                            return IS_CHINA_MAINLAND_MACHINE;
                        }

                        public static boolean isIsChinaMainlandNetwork() {
                            return IS_CHINA_MAINLAND_MACHINE;
                        }
                    }
                    """);
            byte[] patched = transformer.transform(null, RegionUtilsTransformer.TARGET_CLASS, null, null, original);
            assertNotNull(patched, "应改写字节码");
            Class<?> clazz = load(patched);
            assertFalse(invokeBoolean(clazz, "isIsChinaMainlandMachine"), "isIsChinaMainlandMachine()");
            assertFalse(invokeBoolean(clazz, "isIsChinaMainlandNetwork"), "isIsChinaMainlandNetwork()");
            assertFalse(readField(clazz, "IS_CHINA_MAINLAND_MACHINE"), "IS_CHINA_MAINLAND_MACHINE");
        });

        // 场景 3：没有可改写的字段初始化，只剩公开方法，策略 3 命中
        test("只剩公开方法（策略 3 兜底）", () -> {
            byte[] original = compile("""
                    package org.jackhuang.hmcl.util;

                    public final class RegionUtils {
                        public static boolean isIsChinaMainlandMachine() {
                            return true;
                        }

                        public static boolean isIsChinaMainlandNetwork() {
                            return true;
                        }
                    }
                    """);
            byte[] patched = transformer.transform(null, RegionUtilsTransformer.TARGET_CLASS, null, null, original);
            assertNotNull(patched, "应改写字节码");
            Class<?> clazz = load(patched);
            assertFalse(invokeBoolean(clazz, "isIsChinaMainlandMachine"), "isIsChinaMainlandMachine()");
            assertFalse(invokeBoolean(clazz, "isIsChinaMainlandNetwork"), "isIsChinaMainlandNetwork()");
        });

        // 场景 4：目标类结构完全不认识，应放弃改写而不是乱改
        test("无法识别的 RegionUtils 结构（安全放弃）", () -> {
            byte[] original = compile("""
                    package org.jackhuang.hmcl.util;

                    public final class RegionUtils {
                        private static final String NOTE = "unknown layout";
                    }
                    """);
            byte[] patched = transformer.transform(null, RegionUtilsTransformer.TARGET_CLASS, null, null, original);
            assertNull(patched, "无法识别时应返回 null");
        });

        // 场景 5：非目标类不应被处理
        test("非目标类直接放行", () -> {
            byte[] original = compile("""
                    package org.example;

                    public final class Unrelated {
                        public static boolean isIsChinaMainlandMachine() {
                            return true;
                        }
                    }
                    """);
            byte[] patched = transformer.transform(null, "org/example/Unrelated", null, null, original);
            assertNull(patched, "非目标类应返回 null");
        });

        System.out.println();
        System.out.println("测试完成：" + passed + " 通过，" + failed + " 失败");
        if (failed > 0) {
            System.exit(1);
        }
    }

    // ---------------------------------------------------------------- 测试框架小工具

    private interface TestCase {
        void run() throws Exception;
    }

    private static void test(String name, TestCase testCase) {
        try {
            testCase.run();
            passed++;
            System.out.println("[PASS] " + name);
        } catch (Throwable throwable) {
            failed++;
            System.out.println("[FAIL] " + name + " -> " + throwable);
            throwable.printStackTrace(System.out);
        }
    }

    private static void assertNotNull(Object value, String message) {
        if (value == null) {
            throw new AssertionError(message + "：实际为 null");
        }
    }

    private static void assertNull(Object value, String message) {
        if (value != null) {
            throw new AssertionError(message + "：应为 null");
        }
    }

    private static void assertFalse(boolean value, String message) {
        if (value) {
            throw new AssertionError(message + "：应为 false，实际为 true");
        }
    }

    private static boolean invokeBoolean(Class<?> clazz, String methodName) throws Exception {
        Method method = clazz.getMethod(methodName);
        return (boolean) method.invoke(null);
    }

    private static boolean readField(Class<?> clazz, String fieldName) throws Exception {
        Field field = clazz.getDeclaredField(fieldName);
        field.setAccessible(true);
        return field.getBoolean(null);
    }

    /**
     * 编译一段 Java 源码并返回生成的 class 字节码。
     */
    private static byte[] compile(String source) throws IOException {
        Path workDir = Files.createTempDirectory("hmcl-region-patch-test");
        String fileName = extractClassName(source) + ".java";
        Path sourceFile = workDir.resolve(fileName);
        Files.writeString(sourceFile, source, StandardCharsets.UTF_8);
        Path outputDir = workDir.resolve("classes");
        Files.createDirectories(outputDir);

        var compiler = javax.tools.ToolProvider.getSystemJavaCompiler();
        if (compiler == null) {
            throw new IllegalStateException("当前 JVM 没有 javac，请使用 JDK 而不是 JRE 运行自测");
        }
        int result = compiler.run(null, null, null,
                "--release", "17",
                "-d", outputDir.toString(),
                sourceFile.toString());
        if (result != 0) {
            throw new IllegalStateException("测试源码编译失败");
        }

        // 测试源码的包名可能是 org.jackhuang.hmcl.util 也可能是 org.example，直接找编译产物
        Path classFile;
        try (var stream = Files.walk(outputDir)) {
            classFile = stream
                    .filter(path -> path.toString().endsWith(".class"))
                    .findFirst()
                    .orElseThrow(() -> new IllegalStateException("编译后找不到 class 文件"));
        }
        return Files.readAllBytes(classFile);
    }

    private static String extractClassName(String source) {
        for (String line : source.split("\n")) {
            String trimmed = line.trim();
            if (trimmed.startsWith("public final class ")) {
                String rest = trimmed.substring("public final class ".length()).trim();
                return rest.split("[\\s{]", 2)[0];
            }
        }
        throw new IllegalArgumentException("无法从源码中提取类名");
    }

    private static Class<?> load(byte[] classBytes) throws Exception {
        try (var loader = new SingleClassLoader(classBytes)) {
            return loader.loadClass("org.jackhuang.hmcl.util.RegionUtils");
        }
    }

    private static final class SingleClassLoader extends URLClassLoader {
        private final byte[] classBytes;

        private SingleClassLoader(byte[] classBytes) {
            super(new URL[0], SelfTest.class.getClassLoader());
            this.classBytes = classBytes;
        }

        @Override
        protected Class<?> findClass(String name) throws ClassNotFoundException {
            if ("org.jackhuang.hmcl.util.RegionUtils".equals(name)) {
                return defineClass(name, classBytes, 0, classBytes.length);
            }
            return super.findClass(name);
        }
    }

    private SelfTest() {
    }
}
