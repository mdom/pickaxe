package App::pickaxe::Controller;
use Mojo::Base -signatures, -base;
use Curses;
use Mojo::File 'tempfile';
use Mojo::Util 'decode', 'encode';
use App::pickaxe::Api;
use App::pickaxe::DisplayMsg 'display_msg';
use App::pickaxe::SelectOption 'askyesno', 'select_option';
use App::pickaxe::Getline 'getline';
use App::pickaxe::Keys 'getkey';
use Algorithm::Diff;

has maxlines => sub { $LINES - 3 };

has api => sub { App::pickaxe::Api->new( base_url => shift->config->{base_url} ) };

sub open_in_browser ( $self, $key ) {
    use IPC::Cmd;
    my $title = $self->pages->current->{title};
    IPC::Cmd::run( command => [ 'xdg-open', $self->api->url_for($title) ] );
}

sub dump ($self, $data) {
    endwin;
    use Data::Dumper;
    die Dumper $data;
}

sub add_page ( $self, $key ) {
    my $title = getline( "Page name: ", { history => $self->find_history } );
    if ( !$title ) {
        display_msg("Aborted.");
        return;
    }
    if ( $self->api->page($title) ) {
        display_msg("Title has already been taken.");
        return;
    }
    my $new_text = $self->call_editor(tempfile);

    if ($new_text) {
        if ( askyesno("Save page $title?") ) {
            $self->api->save( $title, $new_text );
            $self->set_pages( $self->api->pages );
            display_msg('Saved.');
        }
        else {
            display_msg('Not saved.');
        }
    }
    else {
        display_msg('Discard unmodified page.');
    }
}

sub save_page ( $self, $title, $new_text, $version = undef ) {
    while (1) {
        if ( $self->api->save( $title, $new_text, $version ) ) {
            display_msg('Saved.');
        }
        else {
            my $option =
              select_option( 'Conflict detected', qw(Edit Abort Overwrite) );
            if ( ! defined $option or $option eq 'abort' ) {
                display_msg('Not saved.');
            }
            elsif ( $option eq 'edit' ) {
                ( $new_text, $version ) =
                  $self->handle_conflict( $title, $new_text );
                if ( defined $new_text ) {
                    next;
                }
                display_msg('Not saved.');
            }
            elsif ( $option eq 'overwrite' ) {
                $self->api->save( $title, $new_text );
                display_msg('Saved.');
            }
        }
        last;
    }
}

sub update_current_page ($self) {
    $self->pages->set(
        $self->api->page( $self->pages->current->{title} ) );
}

sub edit_page ( $self, $key ) {
    $self->update_current_page;
    my $title   = $self->pages->current->{title};
    my $version = $self->pages->current->{version};
    my $text    = $self->pages->current->{text};

    $text =~ s/\r//g;
    my $tempfile = tempfile;
    $tempfile->spurt( encode( 'utf8', $text ) );

    my $new_text = $self->call_editor($tempfile);
    if ( $text ne $new_text ) {
        if ( askyesno("Save page $title?") ) {
            $self->save_page( $title, $new_text, $version );
        }
        else {
            display_msg('Not saved.');
        }
    }
    else {
        display_msg('Discard unmodified page.');
    }
    $self->update_current_page;
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
    $self->redraw;
    return decode( 'utf8', $file->slurp );
}

sub update_helpbar ($self) {
    move( 0, 0 );
    clrtoeol;
    attron(A_REVERSE);
    my $help = $self->help_summary;
    $help = substr( $help, 0, $COLS - 1 );
    addstring( $help . ( ' ' x ( $COLS - length($help) ) ) );
    attroff(A_REVERSE);
    refresh;
}

sub update_statusbar ($self) {
    move( $LINES - 2, 0 );
    clrtoeol;
    attron(A_REVERSE);
    my ( $left, $right ) = $self->status;
    $right //= '';
    $left  //= '';
    $left  = substr( $left,  0, $COLS - 1 );
    $right = substr( $right, 0, $COLS - 1 );
    addstring( $left . ( ' ' x ( $COLS - length($left) ) ) );
    addstring( $LINES - 2, $COLS - 1 - length($right), $right );
    attroff(A_REVERSE);
    refresh;
}

sub display_help ( $self, $key ) {
    endwin;
    system( 'perldoc', $0 );
    refresh;
}

sub redraw ($self) {
    $self->update_statusbar;
    $self->update_helpbar;
}

sub run ($self) {
    $self->redraw;
    while (1) {
        my $key = getkey;
        display_msg('');

        if ( my $funcname =
               $self->config->{maps}->{ $self->map }->{$key}
            || $self->bindings->{$key} )
        {
            if ( $funcname eq 'quit' ) {
                last;
            }
            ## TODO Check if function exists on startup!
            $self->$funcname($key);
        }
        elsif ( $key eq KEY_RESIZE ) {
            resize_window();
        }
        else {
            display_msg("Key is not bound.");
        }
    }
}

sub delete_page ( $self, $key ) {
    my $title = $self->pages->current->{title};
    if ( askyesno("Delete page $title?") ) {
        my $error = $self->api->delete($title);
        if ($error) {
            display_msg("Error: $error");
        }
        else {
            $self->pages->delete;
            display_msg("Deleted.");
        }
    }
}

sub query_connection_details ($self) {
    my $apikey = $self->config->{apikey} || $ENV{REDMINE_APIKEY};
    if ( $apikey ) {
        $self->config->{base_url}->query( key => $apikey );
    }
    else {
        my $username = $self->config->{username} || getline("Username: ");
        my $password;
        if ( @{$self->config->{pass_cmd}}) {
            endwin;
            my $cmd = "@{$self->config->{pass_cmd}}";
            $password = qx($cmd);
            chomp($password);
        }
        else {
            $password = $self->config->{password} || getline( "Password: ", { password => 1 } );
        }
        $self->config->{base_url}->userinfo("$username:$password");
    }
}

1;
