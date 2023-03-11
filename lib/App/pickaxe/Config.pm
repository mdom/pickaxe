package App::pickaxe::Config;
use Mojo::Base -signatures, -base;
use Mojo::Util 'decode';
use Mojo::File 'path';
use Text::ParseWords 'shellwords';
use Curses;

has 'username';
has 'password';
has 'apikey';
has 'base_url';

has pass_cmd    => sub { [] };
has yank_cmd    => sub { ['xclip'] };
has keybindings => sub {
    return {
        project_menu => {
            '<Return>' => 'select_project',
        },
        link_browser => {
            '<Return>' => 'follow_link',
        },
        attachment_menu => {
            's'        => 'save_attachment',
            '<Return>' => 'view_attachment',
            a          => 'add_attachment',
            A          => 'add_attachment',
            D          => 'delete_attachment',
        },
        index => {
            e          => 'edit_page',
            d          => 'diff_page',
            a          => 'add_page',
            A          => 'add_attachment',
            b          => 'open_in_browser',
            c          => 'switch_project',
            s          => 'search',
            o          => 'set_order',
            O          => 'set_reverse_order',
            D          => 'delete_page',
            y          => 'yank_url',
            v          => 'view_attachments',
            f          => 'follow_links',
            s          => 'search',
            '<Return>' => 'view_page',
            '%'        => 'toggle_threading',
            '?'        => 'display_help',
        },
        pager => {
            e   => 'edit_page',
            f   => 'follow_links',
            v   => 'view_attachments',
            a   => 'add_page',
            d   => 'diff_page',
            b   => 'open_in_browser',
            y   => 'yank_url',
            J   => 'next_item',
            K   => 'prev_item',
            o   => 'set_order',
            O   => 'set_reverse_order',
            D   => 'delete_page',
            '$' => 'sync_pages',
            '<' => 'prev_version',
            '>' => 'next_version',
            '[' => 'prev_version',
            ']' => 'next_version',
            '{' => 'first_version',
            '}' => 'latest_version',
        }
    };
};

has index_time_format => "%Y-%m-%d %H:%M:%S";
has index_format      => '%4n %-22u %l%t';
has attach_format     => '%4n %f %>  [%t %5s]';
has project_format    => '%4n %p';
has link_format       => '%4n %l';
has diff_pager_format => 'pickaxe: Diff %t --- rev %v by %a +++ rev %V by %A';

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
