package App::pickaxe;
use Mojo::Base -signatures, -base;
use Curses;
use Mojo::URL;
use Mojo::File 'tempfile';
use Mojo::Util 'decode', 'encode';
use App::pickaxe::Api;
use App::pickaxe::DisplayMsg 'display_msg';

has maxlines => sub { $LINES - 3 };

has base => sub {  Mojo::URL->new('https://redmine.hal.taz.de/projects/taz_wiki_edv/') };

has api => sub { App::pickaxe::Api->new };

sub edit_page ($self) {
    endwin;
    my $page = $self->pages->[$self->selected]->{title};
    my $res  = get( $self->base->clone->path("wiki/$page.json") );
    if ( !$res->is_success ) {
        $self->display_msg( "Can't retrieve $page: " . $res->msg );
        return;
    }
    my $text     = $res->json->{wiki_page}->{text};
    my $tempfile = tempfile;
    $tempfile->spurt( encode( 'utf8', $text ) );
    system( 'vim', $tempfile->to_string );

    $self->redraw;

    my $new_text = decode( 'utf8', $tempfile->slurp );

    if ( $new_text ne $text ) {
        if ( askyesno("Save page $page?") ) {
            put( $self->base->clone->path("wiki/$page.json"), $text );
        }
    }
    else {
        display_msg('Discard unmodified page.');
    }
}

sub update_helpbar {
    move( 0, 0 );
    clrtoeol;
    attron(A_REVERSE);
    my $help = "q:Quit e:Edit s:Search ?:help";
    addstring( $help . ( ' ' x ( $COLS - length($help) ) ) );
    attroff(A_REVERSE);
    refresh;
}

sub update_statusbar ($self) {
    move( $LINES - 2, 0 );
    clrtoeol;
    attron(A_REVERSE);
    my $base   = $self->base->clone->query( key => undef );
    my $status = "pickaxe: $base";
    addstring( $status . ( ' ' x ( $COLS - length($status) ) ) );
    attroff(A_REVERSE);
    refresh;
}

sub display_help ($self) {
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
            $self->$funcname;
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
        $self->base->query( key => $ENV{REDMINE_APIKEY} );
    }
    else {
        my $username = getline( "Username: " );
        my $password = getline( "Password: ", { password => 1 } );
        $self->base->userinfo("$username:$password");
    }
}



1;
