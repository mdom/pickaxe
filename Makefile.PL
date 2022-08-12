use ExtUtils::MakeMaker;

WriteMakefile(
    NAME         => "App::pickaxe",
    EXE_FILES    => ['bin/pickaxe'],
    VERSION_FROM => 'bin/pickaxe',
    PREREQ_PM    => {
        'Mojolicious' => 0,
        'Curses'      => 0,
    },
);

