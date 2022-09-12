package App::pickaxe::Config;
use Mojo::Base -signatures, -base;
use Mojo::Util 'decode';
use Mojo::File 'path';
use Text::ParseWords 'shellwords';
use Mojo::URL;
use Curses;

has 'username';
has 'password';

has filter_cmd  => sub { [qw(pandoc -f textile -t plain)] };
has filter_mode => 'no';
has pass_cmd    => sub { [] };
has yank_cmd    => sub { ['xclip'] };
has keybindings => sub {
    {
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
            '<PageDown>' => 'next_page',
            '<PageUp>'   => 'prev_page',
            '<Left>'     => 'prev_page',
            '<Right>'    => 'next_page',
            '<Space>'    => 'next_page',
            '<Resize>'   => 'redraw',
            s            => 'search',
            o            => 'set_order',
            O            => 'set_reverse_order',
            D            => 'delete_page',
            '/'          => 'find',
            '<Esc>/'     => 'find_reverse',
            'n'          => 'find_next',
            'N'          => 'find_next_reverse',
            '?'          => 'display_help',
            '$'          => 'update_pages',
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
            '^L'         => 'force_redraw',
            'y'          => 'yank_url',
        },
        pager => {
            'q'           => 'quit',
            'e'           => 'edit_page',
            'w'           => 'create_page',
            '<PageDown>'  => 'next_page',
            '<Space>'     => 'next_page',
            '<PageUp>'    => 'prev_page',
            '<Down>'      => 'next_line',
            '<Up>'        => 'prev_line',
            '<Return>'    => 'next_line',
            '<Backspace>' => 'prev_line',
            '<Resize>'    => 'redraw',
            '%'           => 'toggle_filter_mode',
            '<Home>'      => 'top',
            '<End>'       => 'bottom',
            '<Left>'      => 'scroll_left',
            '<Right>'     => 'scroll_right',
            '/'           => 'find',
            '<Esc>/'      => 'find_reverse',
            'n'           => 'find_next',
            'N'           => 'find_next_reverse',
            '<Backslash>' => 'find_toggle',
            o             => 'open_in_browser',
            J             => 'next_item',
            K             => 'prev_item',
            D             => 'delete_page',
            '^L'          => 'force_redraw',
            'y'           => 'yank_url',
            '?'           => 'display_help',
        }
    }
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
