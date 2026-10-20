package io.github.octautumn.hmclpatch;

import java.lang.reflect.Field;

/**
 * 针对真实 HMCL jar 的集成验证探针。
 * <p>
 * 由构建脚本在 {@code -javaagent:hmcl-region-patch.jar} 下运行：
 * <pre>
 * java -javaagent:dist/hmcl-region-patch.jar -cp build/test-classes:HMCL.jar \
 *      io.github.octautumn.hmclpatch.RealJarProbe
 * </pre>
 * 三项读数全部为 false 时退出码为 0。
 */
public final class RealJarProbe {

    public static void main(String[] args) throws Exception {
        Class<?> regionUtils = Class.forName("org.jackhuang.hmcl.util.RegionUtils");
        boolean machine = (boolean) regionUtils.getMethod("isIsChinaMainlandMachine").invoke(null);
        boolean network = (boolean) regionUtils.getMethod("isIsChinaMainlandNetwork").invoke(null);

        Field field = regionUtils.getDeclaredField("IS_CHINA_MAINLAND_MACHINE");
        field.setAccessible(true);
        boolean fieldValue = field.getBoolean(null);

        System.out.println("java.version              = " + System.getProperty("java.version"));
        System.out.println("isIsChinaMainlandMachine() = " + machine);
        System.out.println("isIsChinaMainlandNetwork() = " + network);
        System.out.println("IS_CHINA_MAINLAND_MACHINE  = " + fieldValue);

        if (machine || network || fieldValue) {
            System.out.println("RESULT: FAIL");
            System.exit(1);
        }
        System.out.println("RESULT: PASS");
    }

    private RealJarProbe() {
    }
}
