package App::pickaxe::Controller;
use Mojo::Base -signatures, -base;
use Curses;
use Mojo::File 'tempfile';
use Mojo::Util 'decode', 'encode';
use App::pickaxe::Api;
use App::pickaxe::DisplayMsg 'display_msg';
use App::pickaxe::SelectOption 'askyesno';
use App::pickaxe::Getline 'getline';
use IPC::Cmd 'run_forked';

has maxlines => sub { $LINES - 3 };

has api => sub { App::pickaxe::Api->new( base_url => shift->state->base_url ) };

has 'state';

sub pages {
    shift->state->pages;
}

sub open_in_browser ( $self, $key ) {
    use IPC::Cmd;
    my $title = $self->state->pages->current->{title};
    IPC::Cmd::run( command => [ 'xdg-open', $self->api->url_for($title) ] );
}

sub create_page ( $self, $key ) {
    my $title = getline( "Page name: ", { history => $self->find_history } );
    if ( !$title ) {
        display_msg("Aborted.");
        return;
    }
    my $tempfile = tempfile;
    endwin;
    system( 'vim', $tempfile->to_string );
    $self->redraw;

    my $new_text = decode( 'utf8', $tempfile->slurp );

    if ($new_text) {
        if ( askyesno("Save page $title?") ) {
            my $res = $self->api->save( $title, $new_text );
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

sub edit_page ( $self, $key ) {
    my $title   = $self->state->pages->current->{title};
    my $version = $self->state->pages->current->{version};
    my $res     = $self->api->page($title);
    if ( !$res->is_success ) {
        $self->display_msg( "Can't retrieve $title: " . $res->msg );
        return;
    }
    my $text     = $res->json->{wiki_page}->{text};
    my $tempfile = tempfile;
    $tempfile->spurt( encode( 'utf8', $text ) );

    my $new_text = $self->call_editor( $tempfile);

    while (1) {
        if ( $new_text ne $text ) {
            if ( askyesno("Save page $title?") ) {
                my $res = $self->api->save( $title, $new_text, $version );
                if ( $res->is_success ) {
                    display_msg('Saved.');
                }
                elsif ( $res->code == 409 ) {
                    $new_text = $self->handle_conflict( $title, $tempfile, $new_text );
                }
                else {
                    display_msg( 'Error saving wiki page: ' . $res->message );
                }
                last;
            }
            else {
                display_msg('Not saved.');
                last;
            }
        }
        else {
            display_msg('Discard unmodified page.');
            last;
        }
    }
}

sub handle_conflict ( $self, $title, $tempfile, $new_text ) {
    my $res = $self->api->page($title);
    if ( !$res->is_success ) {
        $self->display_msg( "Can't retrieve $title: " . $res->msg );
        return;
    }
    my $text   = $res->json->{wiki_page}->{text};

    my $context_lines_1 = scalar split(/\n/, $text);
    my $context_lines_2 = scalar split(/\n/, $new_text);
    my $context_lines = $context_lines_2 > $context_lines_1 ? $context_lines_2 : $context_lines_1;

    my $diff_cmd = ['diff', '-L', 'remote', '-L', 'local', '-U', $context_lines, '-', $tempfile->to_string ];

    my $result = run_forked( $diff_cmd, { child_stdin => encode( 'utf8', $text ) } );

    $tempfile->spurt( encode( 'utf8', $result->{stdout} ) );
    return $self->call_editor( $tempfile);
}

sub call_editor ($self, $file) {
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
        my $key = getchar;
        display_msg('');

        if ( my $funcname = $self->bindings->{$key} ) {
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

sub query_connection_details ($self) {
    if ( $ENV{REDMINE_APIKEY} ) {
        $self->state->base_url->query( key => $ENV{REDMINE_APIKEY} );
    }
    else {
        my $username = getline("Username: ");
        my $password = getline( "Password: ", { password => 1 } );
        $self->state->base_url->userinfo("$username:$password");
    }
}

1;
