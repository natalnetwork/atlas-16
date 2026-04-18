package br.com.natalnetwork.atlas16.loader;

import java.io.*;
import java.nio.file.*;
import java.util.*;

public class HpsLoader {

    private final String host;
    private final String user;
    private final String remotePath;

    private static final String[] SSH_OPTS = {
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null"
    };

    public HpsLoader(String host, String user) {
        this.host       = host;
        this.user       = user;
        this.remotePath = "/home/root/";
    }

    public void load(Path hackFile) throws IOException, InterruptedException {
        String remote = user + "@" + host;
        String remoteHack = remotePath + hackFile.getFileName();
        String remoteLoader = remotePath + "hps_load";

        System.out.println("[load] Kopiere " + hackFile.getFileName() + " → " + remote + ":" + remotePath);
        scp(hackFile.toString(), remote + ":" + remotePath);

        System.out.println("[load] Starte hps_load auf " + host + "...");
        ssh(remote, remoteLoader + " " + remoteHack);

        System.out.println("[load] Fertig.");
    }

    private void scp(String local, String target) throws IOException, InterruptedException {
        List<String> cmd = new ArrayList<>();
        cmd.add("scp");
        cmd.addAll(Arrays.asList(SSH_OPTS));
        cmd.add(local);
        cmd.add(target);
        run(cmd);
    }

    private void ssh(String remote, String command) throws IOException, InterruptedException {
        List<String> cmd = new ArrayList<>();
        cmd.add("ssh");
        cmd.addAll(Arrays.asList(SSH_OPTS));
        cmd.add(remote);
        cmd.add(command);
        run(cmd);
    }

    private void run(List<String> cmd) throws IOException, InterruptedException {
        Process proc = new ProcessBuilder(cmd)
            .inheritIO()
            .start();
        int exit = proc.waitFor();
        if (exit != 0)
            throw new IOException("Befehl fehlgeschlagen (exit " + exit + "): " + String.join(" ", cmd));
    }
}
