class IO::Stat {
    has $.path;

    method exists {
        ?pir::stat__isi($.path, 0);
    }

    method size {
        pir::stat__isi($.path, 1);
    }

    method isdir {
        ?pir::stat__isi($.path, 2);
    }

    method isdev {
        ?pir::stat__isi($.path, 3);
    }

    method createtime {
        pir::stat__isi($.path, 4);
    }

    method accesstime {
        pir::stat__isi($.path, 5);
    }

    method modifytime {
        pir::stat__isi($.path, 6);
    }

    method changetime {
        pir::stat__isi($.path, 7);
    }

    method backuptime {
        pir::stat__isi($.path, 8);
    }

    method uid {
        pir::stat__isi($.path, 9);
    }

    method gid {
        pir::stat__isi($.path, 10);
    }

    method permissions {
        pir::stat__isi($.path, -3) +& 0o7777;
    }
}

# vim: ft=perl6
