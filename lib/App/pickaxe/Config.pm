package App::pickaxe::Config;
use Mojo::Base -signatures, -base;
use Mojo::Util 'decode';
use Mojo::File 'path';
use Text::ParseWords 'shellwords';
use Mojo::URL;
use Curses;

has 'username';
has 'password';

has pass_cmd    => sub { [] };
has yank_cmd    => sub { ['xclip'] };
has keybindings => sub {
    return {
        attachmentmenu => {
            '<End>'    => 'last_item',
            '<Home>'   => 'first_item',
            '<Down>'   => 'next_item',
            '<Up>'     => 'prev_item',
            j          => 'next_item',
            k          => 'prev_item',
            q          => 'quit',
            's'        => 'save_attachment',
            '<Return>' => 'view_attachment',
        },
        index => {
            '<End>'      => 'last_item',
            '<Home>'     => 'first_item',
            '<Down>'     => 'next_item',
            '<Up>'       => 'prev_item',
            j            => 'next_item',
            k            => 'prev_item',
            e            => 'edit_page',
            a            => 'add_page',
            A            => 'add_attachment',
            b            => 'open_in_browser',
            c            => 'switch_project',
            '<Return>'   => 'view_page',
            '<PageDown>' => 'next_screen',
            '<PageUp>'   => 'prev_page',
            '<Left>'     => 'prev_page',
            '<Right>'    => 'next_screen',
            '<Space>'    => 'next_screen',
            '<Resize>'   => 'render',
            s            => 'search',
            o            => 'set_order',
            O            => 'set_reverse_order',
            D            => 'delete_page',
            d            => 'diff_page',
            '/'          => 'find',
            '<Esc>/'     => 'find_reverse',
            'n'          => 'find_next',
            'N'          => 'find_next_reverse',
            '?'          => 'display_help',
            '$'          => 'sync_pages',
            q            => 'quit',
            1            => 'jump',
            2            => 'jump',
            3            => 'jump',
            4            => 'jump',
            5            => 'jump',
            6            => 'jump',
            7            => 'jump',
            8            => 'jump',
            9            => 'jump',
            0            => 'jump',
            '^L'         => 'force_render',
            'y'          => 'yank_url',
            'v'          => 'view_attachments',
        },
        pager => {
            e             => 'edit_page',
            'v'           => 'view_attachments',
            a             => 'add_page',
            d             => 'diff_page',
            b             => 'open_in_browser',
            'q'           => 'quit',
            'y'           => 'yank_url',
            '$'           => 'sync_pages',
            '<PageDown>'  => 'next_screen',
            '<Space>'     => 'next_screen',
            '<PageUp>'    => 'prev_page',
            '<Down>'      => 'next_line',
            '<Up>'        => 'prev_line',
            '<Return>'    => 'next_line',
            '<Backspace>' => 'prev_line',
            '<Resize>'    => 'render',
            '<Home>'      => 'top',
            '<End>'       => 'bottom',
            '<Left>'      => 'scroll_left',
            '<Right>'     => 'scroll_right',
            '/'           => 'find',
            '<Esc>/'      => 'find_reverse',
            'n'           => 'find_next',
            'N'           => 'find_next_reverse',
            '<Backslash>' => 'find_toggle',
            J             => 'next_item',
            K             => 'prev_item',
            '^L'          => 'force_render',
            '?'           => 'display_help',
            o             => 'set_order',
            O             => 'set_reverse_order',
            D             => 'delete_page',
            '<'           => 'prev_version',
            '>'           => 'next_version',
            '['           => 'prev_version',
            ']'           => 'next_version',
            '{'           => 'first_version',
            '}'           => 'latest_version',
        }
    };
};

has index_time_format => "%Y-%m-%d %H:%M:%S";
has index_format      => '%4n %-22u %t';

sub base_url ( $self, $url = undef ) {
    if ($url) {
        if ( $url !~ m{/$} ) {
            $url .= '/';
        }
        $self->{base_url} = Mojo::URL->new($url);
    }
    return $self->{base_url};
}

sub new ($class) {
    my $file = ( $ENV{XDG_CONFIG_HOME} || "$ENV{HOME}/.config" )
      . "/pickaxe/pickaxe.conf";
    my $config = bless {}, $class;
    if ( !-e $file ) {
        return $config;
    }
    my $path   = path($file);
    my $handle = $path->open('<:encoding(UTF-8)');
    my $has_errors;
    my $last_line;
    while (<$handle>) {
        chomp;
        s/#.*$//;
        next if /^\s*$/;

        ## handle line continuations with \
        if ($last_line) {
            $_         = $last_line . $_;
            $last_line = undef;
        }
        if (s/\\\s*$//) {
            $last_line = $_;
            next;
        }

        my ( $cmd, @args ) = shellwords($_);
        if ( $cmd eq 'set' ) {
            my ( $key, $value, @rest ) = @args;
            if ( !$config->can($key) ) {
                warn "Error in $file, line $.: $key: unknown variable\n";
                $has_errors++;
            }
            elsif ( ref( $config->$key ) eq 'ARRAY' ) {
                $config->$key( [ $value, @rest ] );
            }
            else {
                $config->$key($value);
            }
        }
        elsif ( $cmd eq 'bind' ) {
            my ( $map, $key, $function ) = @args;
            $config->keybindings->{$map}->{$key} = $function;
        }
        else {
            warn "Error in $file, line $.: $cmd: unknown command\n";
            $has_errors++;
        }
    }
    if ($has_errors) {
        say "Press any key to continue...";
        <STDIN>;
    }
    return $config;
}

1;
