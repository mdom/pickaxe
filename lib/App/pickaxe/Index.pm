package App::pickaxe::Index;
use Mojo::Base -signatures, 'App::pickaxe::GUI::Select';

use App::pickaxe::Api;
use App::pickaxe::Getline 'getline';
use App::pickaxe::Keys 'getkey';
use App::pickaxe::Pager;
use App::pickaxe::SelectOption 'select_option', 'askyesno';

use Algorithm::Diff;
use Curses;
use Mojo::File 'tempfile';
use Mojo::Util 'decode', 'encode';
use POSIX 'strftime';

has 'config';
has pages => sub { [] };

has helpbar =>
  "q:Quit a:Add e:Edit s:Search /:find b:Browse o:Order D:delete ?:help";

has 'order' => 'reverse_updated_on';

has api =>
  sub { App::pickaxe::Api->new( base_url => shift->config->{base_url} ) };

sub statusbar ($self) {
    my $base = $self->config->{base_url}->clone->query( key => undef );
    return "pickaxe: $base";
}

sub current_page ($self) {
    $self->pages->[ $self->current_line ];
}

sub format_time ( $self, $time ) {
    my $strftime_fmt = $self->config->index_time_format;
    my $redmine_fmt  = '%Y-%m-%dT%H:%M:%SZ';

    # return gmtime->strptime( $time, $redmine_fmt )->strftime($strftime_fmt);
    ## This is a microoptimation of the above statement.
    my ( $year, $mon, $mday, $hour, $min, $sec ) = split( /[:TZ-]/, $time );
    $mon  -= 1;
    $year -= 1900;
    strftime( $strftime_fmt, $sec, $min, $hour, $mday, $mon, $year );
}

sub update_current_page ($self) {
    $self->pages->set( $self->api->page( $self->pages->current->{title} ) );
}

sub open_in_browser ( $self, $key ) {
    return if $self->empty;
    use IPC::Cmd;
    IPC::Cmd::run( command => [ 'xdg-open', $self->current_page->url ] );
}

sub yank_url ( $self, @ ) {
    my $url = $self->pages->current->url;
    open( my $xclip, '|-', @{ $self->config->yank_cmd } )
      or $self->display_msg("Can't yank url: $!");
    print $xclip $url;
    close $xclip;
    $self->display_msg("Copied url to clipboard.");
}

sub add_page ( $self, $key ) {
    state $history = [];
    my $title = getline( "Page name: ", { history => $history } );
    if ( !$title ) {
        $self->display_msg("Aborted.");
        return;
    }
    if ( $self->api->page($title) ) {
        $self->display_msg("Title has already been taken.");
        return;
    }
    my $new_text = $self->call_editor(tempfile);

    if ($new_text) {
        if ( askyesno("Save page $title?") ) {
            $self->api->save( $title, $new_text );
            $self->update_pages;
            $self->display_msg('Saved.');
        }
        else {
            $self->display_msg('Not saved.');
        }
    }
    else {
        $self->display_msg('Discard unmodified page.');
    }
}

sub save_page ( $self, $title, $new_text, $version = undef ) {
    while (1) {
        if ( $self->api->save( $title, $new_text, $version ) ) {
            $self->display_msg('Saved.');
        }
        else {
            my $option =
              select_option( 'Conflict detected', qw(Edit Abort Overwrite) );
            if ( !defined $option or $option eq 'abort' ) {
                $self->display_msg('Not saved.');
            }
            elsif ( $option eq 'edit' ) {
                ( $new_text, $version ) =
                  $self->handle_conflict( $title, $new_text );
                if ( defined $new_text ) {
                    next;
                }
                $self->display_msg('Not saved.');
            }
            elsif ( $option eq 'overwrite' ) {
                $self->api->save( $title, $new_text );
                $self->display_msg('Saved.');
            }
        }
        last;
    }
}

sub edit_page ( $self, $key ) {
    return if $self->empty;

    my $page = $self->api->page( $self->current_page->{title} );

    my $title   = $page->{title};
    my $version = $page->{version};
    my $text    = $page->{text};

    $text =~ s/\r//g;
    my $tempfile = tempfile;
    $tempfile->spurt( encode( 'utf8', $text ) );

    my $new_text = $self->call_editor($tempfile);
    if ( $text ne $new_text ) {
        if ( askyesno("Save page $title?") ) {
            $self->save_page( $title, $new_text, $version );
        }
        else {
            $self->display_msg('Not saved.');
        }
    }
    else {
        $self->display_msg('Discard unmodified page.');
    }
    $self->pages->[ $self->current_line ] = $self->api->page( $title );
}

sub handle_conflict ( $self, $title, $old_text ) {
    my $page     = $self->api->page($title);
    my $new_text = $page->{text};
    $new_text =~ s/\r//g;
    my $version = $page->{version};

    my @seq1 = split( /\n/, $old_text );
    my @seq2 = split( /\n/, $new_text );

    my $diff = Algorithm::Diff->new( \@seq1, \@seq2 );

    my $diff_output = '';
    while ( $diff->Next ) {
        if ( my @context = $diff->Same ) {
            $diff_output .= " $_\n" for @context;
            next;
        }
        $diff_output .= "-$_\n" for $diff->Items(1);
        $diff_output .= "+$_\n" for $diff->Items(2);
    }

    my $tempfile = tempfile;
    $tempfile->spurt( encode( 'utf8', $diff_output ) );
    my $resolved_text;
    while (1) {
        $resolved_text = $self->call_editor($tempfile);
        if ( $resolved_text =~ /^(?:\+|\-)/sm ) {
            my $option =
              select_option( 'Unresolved conflicts', qw(Edit Abort) );
            if ( !defined $option or $option eq 'abort' ) {
                return;
            }
            elsif ( $option eq 'edit' ) {
                next;
            }
        }
        last;
    }
    $resolved_text =~ s/^ //smg;
    return $resolved_text, $version;
}

sub call_editor ( $self, $file ) {
    endwin;
    my $editor = $ENV{VISUAL} || $ENV{EDITOR} || 'vi';
    system( $editor, $file->to_string );
    # $self->render;
    return decode( 'utf8', $file->slurp );
}

sub display_help ( $self, $key ) {
    endwin;
    system( 'perldoc', $0 );
    refresh;
}

sub delete_page ( $self, $key ) {
    return if $self->empty;
    my $title = $self->current_page->{title};
    if ( askyesno("Delete page $title?") ) {
        if ( my $error = $self->api->delete($title) ) {
            $self->display_msg("Error: $error");
            return;
        }
        delete $self->pages->[ $self->current_line ];
        $self->update_pages;
        $self->display_msg("Deleted.");
    }
}

sub query_connection_details ($self) {
    my $apikey = $self->config->{apikey} || $ENV{REDMINE_APIKEY};
    if ($apikey) {
        $self->api->base_url->query( key => $apikey );
    }
    else {
        my $username = $self->config->{username} || getline("Username: ");
        if ( !$username ) {
            die "No username was provided.";
        }
        my $password;
        if ( @{ $self->config->pass_cmd } ) {
            endwin;
            my $cmd = "@{$self->config->{pass_cmd}}";
            $password = qx($cmd);
            chomp($password);
        }
        else {
            $password = $self->config->{password}
              || getline( "Password: ", { password => 1 } );
        }
        if ( !$password ) {
            die "No password was provided.";
        }
        $self->api->base_url->userinfo("$username:$password");
    }
}

sub compile_index_format ($self) {
    my $index_fmt = $self->config->index_format;

    my $fmt = '';
    my @args;

    my %identifier = (
        n => sub { $_[0]->{index} },
        t => sub { my $t = $_[0]->{title}; $t =~ s/_/ /g; $t },
        u => sub { $self->format_time( $_[0]->{'updated_on'} ) },
        c => sub { $self->format_time( $_[0]->{'created_on'} ) },
        v => sub { $_[0]->{version} },
    );

    while (1) {
        if ( $index_fmt =~ /\G%(-?\d+(?:.\d)?)?([a-zA-Z])/gc ) {
            my ( $mod, $format ) = ( $1, $2 );
            $mod //= '';
            if ( my $i = $identifier{$format} ) {
                $fmt .= "%${mod}s";
                push @args, $i;
            }
            else {
                die "Unknown format specifier <$format>\n";
            }
        }
        elsif ( $index_fmt =~ /\G([^%]+)/gc ) {
            $fmt .= $1;
        }
        elsif ( $index_fmt =~ /\G$/gc ) {
            last;
        }
    }
    return $fmt, @args;
}

my %sort_options = (
    updated => 'updated_on',
    created => 'created_on',
    title   => 'title',
);

sub set_order ( $self, $key ) {
    my $order = select_option( 'Sort', qw(Updated Created Title) );
    if ($order) {
        $self->order( $sort_options{$order} );
        $self->update_pages;
    }
}

sub set_reverse_order ( $self, $key ) {
    my $order = select_option( 'Rev-Sort', qw(Updated Created Title) );
    if ($order) {
        $self->order("reverse_$sort_options{$order}");
        $self->update_pages;
    }
}

sub view_page ( $self, $key ) {
    App::pickaxe::Pager->new( config => $self->config, index => $self )->run;
    $self->render;
}

sub set_pages ( $self, $pages ) {

    my $order = $self->order =~ s/^reverse_//r;

    $pages = [ sort { $a->{$order} cmp $b->{$order} } @$pages ];

    if ( $self->order =~ /^reverse_/ ) {
        $pages = [ reverse @$pages ];
    }

    $self->pages($pages);

    my ( $fmt, @args ) = $self->compile_index_format;
    my @lines;
    my $x = 1;
    for my $page ( $self->pages->@* ) {
        $page->{index} = $x++;
        push @lines, sprintf( $fmt, map { $_->($page) } @args );
    }
    $self->set_lines(@lines);
}

sub search ( $self, $key ) {
    state $history = [];
    my $query =
      getline( "Search for pages matching: ", { history => $history } );
    if ( $query eq 'all' ) {
        $self->update_pages;
    }
    elsif ( $query eq '' ) {
        $self->display_msg('To view all messages, search for "all".');
    }
    else {
        my $pages = $self->api->search($query);

        if ( !$pages ) {
            $self->display_msg('No matches found.');
            return;
        }
        $self->set_pages($pages);
        $self->display_msg('To view all messages, search for "all".');
    }
}

sub switch_project ( $self, $key ) {
    my %projects = map { $_ => 1 } @{ $self->api->projects };
    state $history = [];
    my $project = getline(
        'Open project: ',
        {
            history            => $history,
            completion_matches => sub ($word) {
                $word ||= '';
                my @completions;
                for my $project ( keys %projects ) {
                    if ( index( $project, $word ) == 0 ) {
                        push @completions, $project;
                    }
                }
                return @completions;
            }
        }
    );
    return if !$project;
    if ( !exists $projects{$project} ) {
        $self->display_msg("$project is not a project.");
        return;
    }

    $self->api->base_url->path("/projects/$project/");
    $self->update_pages;
}

sub update_pages ($self) {
    my $line = $self->current_line;
    $self->set_pages( $self->api->pages );
    $line = $line > $self->nlines - 1 ? $self->nlines - 1 : $line;
    $self->current_line($line);
}

sub sync_pages ( $self, $key ) {
    $self->update_pages;
    $self->display_msg("Updated.");
}

sub run ($self) {
    $self->query_connection_details;
    $self->update_pages;

    $self->next::method( $self->config->keybindings );
}

1;
