package io.github.octautumn.hmclpatch;

import org.objectweb.asm.ClassReader;
import org.objectweb.asm.ClassWriter;
import org.objectweb.asm.Opcodes;
import org.objectweb.asm.tree.AbstractInsnNode;
import org.objectweb.asm.tree.ClassNode;
import org.objectweb.asm.tree.FieldInsnNode;
import org.objectweb.asm.tree.InsnList;
import org.objectweb.asm.tree.InsnNode;
import org.objectweb.asm.tree.MethodNode;

import java.lang.instrument.ClassFileTransformer;
import java.security.ProtectionDomain;
import java.util.ArrayList;
import java.util.List;

/**
 * 针对 HMCL 的 {@code org.jackhuang.hmcl.util.RegionUtils} 的字节码改写器。
 * <p>
 * 目标：让 {@code IS_CHINA_MAINLAND_MACHINE} 的初始化结果恒为 false，
 * 从而同时解除“中国大陆机器”判断和“中国大陆网络”判断。
 * <p>
 * HMCL 里该字段声明为 {@code private static final boolean = checkMachineIsChinaMainland();}，
 * 不是编译期常量，因此字节码层面存在 &lt;clinit&gt; 的 invokestatic + putstatic，
 * 所有读取点也都是普通的 getstatic，适合在类加载阶段做字节码替换。
 * <p>
 * 按可靠性从高到低尝试三级策略，全部失败时保持原样加载（不破坏 HMCL 启动）：
 * <ol>
 *   <li>把 checkMachineIsChinaMainland() 的方法体改成 return false，覆盖所有调用点；</li>
 *   <li>在 &lt;clinit&gt; 中每条 putstatic IS_CHINA_MAINLAND_MACHINE 之后补一次 false 赋值，
 *       只依赖字段名、不依赖方法名，用来兜底 HMCL 后续给方法改名；</li>
 *   <li>把 public 的 isIsChinaMainlandMachine() / isIsChinaMainlandNetwork() 改成 return false，
 *       保证 UI 判断等公开调用点正确。</li>
 * </ol>
 */
public final class RegionUtilsTransformer implements ClassFileTransformer {

    /** 目标类（internal name）。 */
    public static final String TARGET_CLASS = "org/jackhuang/hmcl/util/RegionUtils";

    /** 目标字段名。 */
    private static final String FIELD_NAME = "IS_CHINA_MAINLAND_MACHINE";

    /** 机器判断方法名。 */
    private static final String CHECK_METHOD = "checkMachineIsChinaMainland";

    /** 对外公开的两个判断方法。 */
    private static final String[] PUBLIC_METHODS = {"isIsChinaMainlandMachine", "isIsChinaMainlandNetwork"};

    @Override
    public byte[] transform(ClassLoader loader, String className, Class<?> classBeingRedefined,
                            ProtectionDomain protectionDomain, byte[] classfileBuffer) {
        // 只关心目标类，其它类（包括 Minecraft 游戏进程加载的类）直接放行
        if (!TARGET_CLASS.equals(className)) {
            return null;
        }
        try {
            byte[] patched = patch(classfileBuffer);
            if (patched == null) {
                PatchLogger.warn("未命中任何注入策略，HMCL 版本可能已重构 RegionUtils，本次将保持原行为");
            }
            return patched;
        } catch (Throwable throwable) {
            // 注入失败绝不能影响 HMCL 启动，返回 null 让 JVM 使用原始字节码
            PatchLogger.error("RegionUtils 字节码改写失败，将使用原始字节码", throwable);
            return null;
        }
    }

    /**
     * 对 RegionUtils 的原始字节码执行注入。
     *
     * @param original 原始 class 字节码
     * @return 改写后的字节码；null 表示没有任何策略命中，不应该替换
     */
    static byte[] patch(byte[] original) {
        ClassReader reader = new ClassReader(original);
        ClassNode classNode = new ClassNode();
        reader.accept(classNode, 0);

        // 策略 1：方法体替换为 return false
        if (patchCheckMethod(classNode)) {
            PatchLogger.info("注入成功：策略 1（checkMachineIsChinaMainland() -> false）");
            return write(reader, classNode);
        }

        // 策略 2：<clinit> 里 putstatic 之后补 false
        if (patchStaticInitializer(classNode)) {
            PatchLogger.info("注入成功：策略 2（<clinit> putstatic 后覆盖为 false）");
            return write(reader, classNode);
        }

        // 策略 3：public 判断方法替换为 return false
        if (patchPublicMethods(classNode)) {
            PatchLogger.info("注入成功：策略 3（public 判断方法 -> false）");
            return write(reader, classNode);
        }

        return null;
    }

    /**
     * 策略 1：把 checkMachineIsChinaMainland() 的方法体整体替换为 return false。
     * <p>
     * 字段初始化会调用它，所以字段自然变成 false；
     * 即使未来 HMCL 在别处也调用这个方法，也会一起返回 false。
     */
    private static boolean patchCheckMethod(ClassNode classNode) {
        for (MethodNode method : classNode.methods) {
            if (CHECK_METHOD.equals(method.name) && "()Z".equals(method.desc)) {
                replaceWithReturnFalse(method);
                return true;
            }
        }
        return false;
    }

    /**
     * 策略 2：在 &lt;clinit&gt; 中每条 putstatic 目标字段之后插入 iconst_0 + putstatic，
     * 把字段的最终值强制改回 false。
     * <p>
     * 这里不依赖检测方法的名字，只依赖字段名，所以能兜住“HMCL 把检测方法改名或内联”这类改动。
     * 在类初始化器里多次写 final static 字段是合法字节码（JVM 不检查赋值次数）。
     * <p>
     * 注意：先收集再插入。直接边遍历边插入会让新插入的 putstatic 指令再次被扫描到，导致死循环。
     */
    private static boolean patchStaticInitializer(ClassNode classNode) {
        for (MethodNode method : classNode.methods) {
            if (!"<clinit>".equals(method.name)) {
                continue;
            }
            List<AbstractInsnNode> targets = new ArrayList<>();
            for (AbstractInsnNode instruction = method.instructions.getFirst(); instruction != null;
                 instruction = instruction.getNext()) {
                if (instruction instanceof FieldInsnNode fieldInsn
                        && fieldInsn.getOpcode() == Opcodes.PUTSTATIC
                        && TARGET_CLASS.equals(fieldInsn.owner)
                        && FIELD_NAME.equals(fieldInsn.name)) {
                    targets.add(instruction);
                }
            }
            if (targets.isEmpty()) {
                continue;
            }
            for (AbstractInsnNode target : targets) {
                InsnList override = new InsnList();
                override.add(new InsnNode(Opcodes.ICONST_0));
                override.add(new FieldInsnNode(Opcodes.PUTSTATIC, TARGET_CLASS, FIELD_NAME, "Z"));
                method.instructions.insert(target, override);
                method.maxStack = Math.max(method.maxStack, 1);
            }
            PatchLogger.debug("<clinit> 中找到 " + targets.size() + " 处目标字段赋值");
            return true;
        }
        return false;
    }

    /**
     * 策略 3：把两个公开判断方法替换为 return false。
     * <p>
     * 只保证 API 层面正确；如果 <clinit> 无法改写，字段本身可能还是 true（init() 会多发一次网络请求），
     * 但这属于兜底，正常情况下不会走到这里。
     */
    private static boolean patchPublicMethods(ClassNode classNode) {
        boolean patched = false;
        for (MethodNode method : classNode.methods) {
            for (String name : PUBLIC_METHODS) {
                if (name.equals(method.name) && "()Z".equals(method.desc)) {
                    replaceWithReturnFalse(method);
                    patched = true;
                }
            }
        }
        return patched;
    }

    /**
     * 清空方法体并替换为 return false（无参数、返回 boolean）。
     */
    private static void replaceWithReturnFalse(MethodNode method) {
        method.instructions.clear();
        method.tryCatchBlocks.clear();
        method.localVariables = null;
        method.visibleLocalVariableAnnotations = null;
        method.invisibleLocalVariableAnnotations = null;
        method.instructions.add(new InsnNode(Opcodes.ICONST_0));
        method.instructions.add(new InsnNode(Opcodes.IRETURN));
        method.maxStack = 1;
        method.maxLocals = 0;
    }

    private static byte[] write(ClassReader reader, ClassNode classNode) {
        // 不要求 ASM 重算栈帧：本次改动不改变栈深度和分支结构，原 StackMapTable 仍然有效
        ClassWriter writer = new ClassWriter(reader, 0);
        classNode.accept(writer);
        return writer.toByteArray();
    }
}
