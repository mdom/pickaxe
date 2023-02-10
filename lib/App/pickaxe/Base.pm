package App::pickaxe::Base;
use Mojo::Base -signatures, -base;
use App::pickaxe::Api;
use Curses;

use Algorithm::Diff;
use Mojo::File 'tempfile';
use Mojo::Util 'decode', 'encode';
use App::pickaxe::Getline 'getline';
use App::pickaxe::SelectOption 'select_option', 'askyesno';

has 'config';
has 'pages' => sub { App::pickaxe::Pages->new  };

has api =>
  sub { App::pickaxe::Api->new( base_url => shift->config->{base_url} ) };

sub open_in_browser ( $self, $key ) {
    return if $self->empty;
    use IPC::Cmd;
    IPC::Cmd::run( command => [ 'xdg-open', $self->pages->current->url ] );
}

sub next_item ( $self, $key ) {
    $self->pages->next;
}

sub empty ($self) {
    $self->pages->empty;
}

my %sort_options = (
    updated => 'updated_on',
    created => 'created_on',
    title   => 'title',
);

sub sort_pages( $self, $order) {
    $self->pages->sort($order);
}

sub set_reverse_order ( $self, $key ) {
    if ( my $order = select_option( 'Rev-Sort', qw(Updated Created Title) )) {
        $self->sort_pages("reverse_$sort_options{$order}");
    }
}

sub set_order ( $self, $key ) {
    if ( my $order = select_option( 'Sort', qw(Updated Created Title) )) {
        $self->sort_pages($sort_options{$order});
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

sub delete_page ( $self, $key ) {
    return if $self->empty;
    my $title = $self->pages->current->title;
    if ( askyesno("Delete page $title?") ) {
        if ( my $error = $self->api->delete($title) ) {
            $self->message("Error: $error");
            return;
        }
        $self->pages->delete_current;
        $self->update_pages;
        $self->message("Deleted.");
    }
}

sub display_help ( $self, $key ) {
    endwin;
    system( 'perldoc', $0 );
    refresh;
}

sub call_editor ( $self, $file ) {
    endwin;
    my $editor = $ENV{VISUAL} || $ENV{EDITOR} || 'vi';
    system( $editor, $file->to_string );
    $self->render;
    return decode( 'utf8', $file->slurp );
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

sub edit_page ( $self, $key ) {
    return if $self->empty;

    my $page = $self->api->page( $self->pages->current->{title} );

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
            $self->message('Not saved.');
        }
    }
    else {
        $self->message('Discard unmodified page.');
    }
    $self->pages->current( $self->api->page( $title ) );
}

sub yank_url ( $self, $key ) {
    my $url = $self->pages->current->url;
    open( my $xclip, '|-', @{ $self->config->yank_cmd } )
      or $self->message("Can't yank url: $!");
    print $xclip $url;
    close $xclip;
    $self->message("Copied url to clipboard.");
}

sub save_page ( $self, $title, $new_text, $version = undef ) {
    while (1) {
        if ( $self->api->save( $title, $new_text, $version ) ) {
            $self->message('Saved.');
        }
        else {
            my $option =
              select_option( 'Conflict detected', qw(Edit Abort Overwrite) );
            if ( !defined $option or $option eq 'abort' ) {
                $self->message('Not saved.');
            }
            elsif ( $option eq 'edit' ) {
                ( $new_text, $version ) =
                  $self->handle_conflict( $title, $new_text );
                if ( defined $new_text ) {
                    next;
                }
                $self->message('Not saved.');
            }
            elsif ( $option eq 'overwrite' ) {
                $self->api->save( $title, $new_text );
                $self->message('Saved.');
            }
        }
        last;
    }
}

sub add_page ( $self, $key ) {
    state $history = [];
    my $title = getline( "Page name: ", { history => $history } );
    if ( !$title ) {
        $self->message("Aborted.");
        return;
    }
    if ( $self->api->page($title) ) {
        $self->message("Title has already been taken.");
        return;
    }
    my $new_text = $self->call_editor(tempfile);

    if ($new_text) {
        if ( askyesno("Save page $title?") ) {
            $self->api->save( $title, $new_text );
            $self->update_pages;
            $self->message('Saved.');
        }
        else {
            $self->message('Not saved.');
        }
    }
    else {
        $self->message('Discard unmodified page.');
    }
}

sub update_pages ($self) {
    $self->set_pages( $self->api->pages );
}

sub set_pages ( $self, $pages ) {

    $self->pages->set($pages);

}

1;
