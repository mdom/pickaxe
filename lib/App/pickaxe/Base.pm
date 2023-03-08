package App::pickaxe::Base;
use Mojo::Base -signatures, -base;

use Curses;
use Mojo::File 'tempfile', 'tempdir';
use Mojo::Loader 'data_section';
use Mojo::Template;
use Mojo::URL;
use Mojo::Util 'decode', 'encode';

use App::pickaxe::Api;
use App::pickaxe::AttachmentMenu;
use App::pickaxe::Getline 'getline';
use App::pickaxe::LinkBrowser;
use App::pickaxe::SelectOption 'select_option', 'askyesno';

has 'config';
has 'pages' => sub { App::pickaxe::Pages->new };

has api => sub {
    App::pickaxe::Api->new( url => Mojo::URL->new( shift->config->base_url ) );
};

sub open_in_browser ( $self, $key ) {
    return if $self->pages->empty;
    use IPC::Cmd;
    IPC::Cmd::run( command => [ 'xdg-open', $self->pages->current->url ] );
}

sub add_attachment ( $self, $key ) {
    my $filename = getline("File to attach: ");
    return if !$filename;
    return if !-f $filename;
    $self->api->attach_files( $self->pages->current->title, $filename );
}

sub follow_links ( $self, $key ) {
    my $re = qr{
    ## textile links
    (?:\[\[ (.*?) (?:\#.*?)? (?:\|.*?)? \]\])
    |
    ## normal urls
    (https?://[^\s?#'"<>]+)
   }x;
    my @links = grep defined, $self->pages->current->text =~ /$re/g;
    if ( !@links ) {
        $self->message('No links found.');
        return;
    }

    my $browser = App::pickaxe::LinkBrowser->new(
        api    => $self->api,
        config => $self->config,
        links  => \@links,
    )->run;
}

sub view_attachments ( $self, $key ) {
    my $menu = App::pickaxe::AttachmentMenu->new(
        attachments => $self->pages->current->attachments,
        api         => $self->api,
        config      => $self->config,
        pages       => $self->pages,
    );
    $menu->run( $self->config->keybindings );
}

my %sort_options = (
    updated => 'updated_on',
    created => 'created_on',
    title   => 'title',
);

sub sort_pages ( $self, $order ) {    # hook
    $self->pages->sort($order);
}

sub set_reverse_order ( $self, $key ) {
    if ( my $order = select_option( 'Rev-Sort', qw(Updated Created Title) ) ) {
        $self->sort_pages("reverse_$sort_options{$order}");
    }
}

sub set_order ( $self, $key ) {
    if ( my $order = select_option( 'Sort', qw(Updated Created Title) ) ) {
        $self->sort_pages( $sort_options{$order} );
    }
}

sub query_connection_details ($self) {
    my $apikey = $self->config->apikey || $ENV{REDMINE_APIKEY};
    if ($apikey) {
        $self->api->base_url->query( key => $apikey );
    }
    else {
        my $username = $self->config->username || getline("Username: ");
        if ( !$username ) {
            die "No username was provided.";
        }
        my $password;
        if ( @{ $self->config->pass_cmd } ) {
            endwin;
            my $cmd = "@{$self->config->pass_cmd}";
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
    return if $self->pages->empty;
    my $title = $self->pages->current->title;
    if ( askyesno("Delete page $title?") ) {
        if ( my $error = $self->api->delete($title) ) {
            $self->message("Error: $error");
            return;
        }
        $self->pages->delete_current;
        $self->message("Deleted.");
    }
}

sub display_manpage ( $self, $key ) {
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

sub parse_hunks ($patch) {
    my @hunks;
    for my $line ( split( "\n", $patch ) ) {
        if ( $line =~ /^\@\@ \s* -(\d+),(\d+) \s* \+(\d+),(\d+) \s* \@\@/x ) {
            push @hunks,
              {
                orig_offset => $1,
                orig_count  => $2,
                new_offset  => $3,
                new_count   => $4,
              };
            next;
        }
        next if !@hunks;
        push @{ $hunks[-1]->{lines} }, $line;
    }
    return @hunks;
}

sub rediff ($patch) {
    my $delta = 0;
    my @new_patch;
    for my $hunk ( parse_hunks($patch) ) {
        my $count = 0;
        for my $line ( @{ $hunk->{lines} } ) {
            if ( $line =~ /^[+ ]/ ) {
                $count++;
            }
        }
        my ( $orig_offset, $orig_count, $new_offset ) =
          @{$hunk}{qw(orig_offset orig_count new_offset)};
        $new_offset += $delta;

        push @new_patch, "@@ -$orig_offset,$orig_count +$new_offset,$count @@";
        push @new_patch, @{ $hunk->{lines} };
        $delta += $count - $hunk->{new_count};
    }
    return join( "\n", @new_patch ) . "\n";
}

sub apply_patch ( $patch_file, $resolved_file, $input_file ) {
    system( 'patch', '-p0', '-i', $patch_file, '-o', $resolved_file,
        $input_file ) == 0;
}

sub edit_patch ( $self, $old_text, $new_text ) {
    ## We need a tempdir here as patch(1) creates files that wouldn't be
    ## cleaned up otherwise
    my $dir = tempdir;

    my $patch = diff( $old_text, $new_text );

    my $template = data_section( 'App::pickaxe::Base', 'patch_template.txt' );
    $patch = Mojo::Template->new->render( $template, $patch );

    my $patch_file = $dir->child('patch')->spurt( encode( 'utf8', $patch ) );
    my $new_patch  = $self->call_editor($patch_file);
    $new_patch =~ s/^#.*?\n//smg;

    $patch_file->spurt( encode( 'utf8', rediff($new_patch) ) );

    my $resolved_file = $dir->child('resolved');
    my $input_file = $dir->child('input')->spurt( encode( 'utf8', $old_text ) );

    if ( apply_patch( $patch_file, $resolved_file, $input_file ) ) {
        return decode( 'utf8', $resolved_file->slurp );
    }
    return;
}

sub handle_conflict ( $self, $title, $old_text ) {
    my $page     = $self->api->page($title);
    my $new_text = $page->text;
    my $version  = $page->{version};

    my $resolved;
    {
        $resolved = $self->edit_patch( $old_text, $new_text );
        if ( !$resolved ) {
            my $option = select_option( 'Patch does no apply cleanly',
                qw(Edit Abort Overwrite) );
            if ( $option eq 'edit' ) {
                redo;
            }
            if ( $option eq 'overwrite' ) {
                return $old_text, $version;
            }
            return;
        }
    }
    return $resolved, $version;
}

sub edit_page ( $self, $key ) {
    return if $self->pages->empty;

    my $page = $self->pages->current;

    my $title   = $page->title;
    my $version = $page->version;
    my $text    = $page->text;

    $text =~ s/\r//g;
    my $tempfile = tempfile;
    $tempfile->spurt( encode( 'utf8', $text ) );

    my $new_text = $self->call_editor($tempfile);
    if ( $text ne $new_text ) {
        if ( askyesno("Save page $title?")
            && $self->save_page( $title, $new_text, $version ) )
        {
            $self->message('Saved.');
            $self->pages->replace_current( $self->api->page($title) );
            return;
        }
        $self->message('Not saved.');
    }
    else {
        $self->message('Discard unmodified page.');
    }
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
    {
        if ( $self->api->save( $title, $new_text, $version ) ) {
            return 1;
        }
        else {
            my $option =
              select_option( 'Conflict detected', qw(Edit Abort Overwrite) );
            if ( !defined $option or $option eq 'abort' ) {
                return 0;
            }
            elsif ( $option eq 'edit' ) {
                ( $new_text, $version ) =
                  $self->handle_conflict( $title, $new_text );
                if ( defined $new_text ) {
                    redo;
                }
                return 0;
            }
            elsif ( $option eq 'overwrite' ) {
                $self->api->save( $title, $new_text );
                return 1;
            }
        }
    }
}

sub diff ( $old_text, $new_text ) {
    my $file1 = tempfile->spurt( encode( 'utf8', $old_text ) );
    my $file2 = tempfile->spurt( encode( 'utf8', $new_text ) );

    my @diff = map { decode( 'utf8', $_ ) } qx(diff -u $file1 $file2);
    return join( '', @diff[ 2 .. $#diff ] );
}

sub diff_page ( $self, $old_version, $new_version ) {
    my $title = $self->pages->current->title;
    if ( $new_version == 1 ) {
        $self->message('No previous version to diff against');
        return;
    }
    my $old_text = $self->api->page( $title, $old_version )->rendered_text;
    my $new_text = $self->api->page( $title, $new_version )->rendered_text;

    my $diff = diff( $old_text, $new_text );
    if ( !$diff ) {
        $self->message("No text changed between $old_version and $new_version");
        return;
    }
    App::pickaxe::UI::Pager->new->set_text($diff)
      ->run( $self->config->keybindings );
    return;
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
            $self->pages->add( $self->api->page($title) );
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

__DATA__

@@ patch_template.txt
<%= $_[0] %>
# To remove '-' lines, make them ' ' lines (context).
# To remove '+' lines, delete them.
# Lines starting with # will be removed.
