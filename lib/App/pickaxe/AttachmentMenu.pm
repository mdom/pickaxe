package App::pickaxe::AttachmentMenu;
use Mojo::Base 'App::pickaxe::UI::Index', -signatures;
use Mojo::File 'tempfile';
use Curses 'refresh';
use Mojo::URL;
use App::pickaxe::Getline 'getline';
use App::pickaxe::Format;
use App::pickaxe::SelectOption 'askyesno';

has helpbar     => "q:Quit s:Save <Ret>:View a:Add D:Delete";
has statusbar   => "pickaxe: Attachments";
has attachments => sub { [] };
has moniker     => 'attachments';
has 'api';
has 'config';
has 'pages';

sub save_attachment ( $self, $key ) {
    return if !$self->attachments->@*;
    my $attachment = $self->attachments->[ $self->current_line ];
    my $path       = Mojo::URL->new( $attachment->content_url )->path;
    my $file = getline( "Save to file: ", { buffer => $attachment->filename } );
    return if !$file;
    $self->api->get($path)->save_to($file);
}

sub add_attachment ( $self, $key ) {
    my $filename = getline("File to attach: ");
    return if !$filename;
    return if !-f $filename;
    my $title = $self->pages->current->title;
    $self->api->attach_files( $title, $filename );
    $self->pages->replace_current( $self->api->page($title) );
    $self->attachments( $self->pages->current->attachments );
    $self->update_lines;
}

sub delete_attachment ( $self, $key ) {
    return if !$self->attachments->@*;
    if ( !askyesno("Delete attachment?") ) {
        return;
    }
    my $err = $self->api->delete_attachment( $self->current_attachment->id );
    if ($err) {
        $self->message("Can't delete attachment: $err");
        return;
    }
    my $title = $self->pages->current->title;
    $self->pages->replace_current( $self->api->page($title) );
    $self->attachments( $self->pages->current->attachments );
    my $current_line = $self->current_line;
    $self->update_lines;
    $self->goto_line($current_line);
}

sub current_attachment ($self) {
    $self->attachments->[ $self->current_line ];
}

sub view_attachment ( $self, $key ) {
    return if !$self->attachments->@*;
    my $file = tempfile;
    my $path = Mojo::URL->new( $self->current_attachment->content_url )->path;
    $self->api->get($path)->save_to( $file->to_string );
    use IPC::Cmd;
    IPC::Cmd::run( command => [ 'xdg-open', $file ] );
    refresh;
}

sub run ( $self, $bindings ) {
    my $fmt = App::pickaxe::Format->new(
        format     => $self->config->attach_format,
        identifier => {
            f => sub { $_[0]->filename },
            t => sub { $_[0]->content_type || 'application/octetstream' },
            s => sub { format_size( $_[0]->filesize || 0 ) },
            n => sub { state $i = 1; $i++ },
        },
    );

    $self->on( resize => sub { $self->update_lines } );
    $self->update_lines;
    $self->next::method($bindings);
}

sub update_lines ($self) {
    my $fmt = App::pickaxe::Format->new(
        format     => $self->config->attach_format,
        identifier => {
            f => sub { $_[0]->filename },
            t => sub { $_[0]->content_type || 'application/octetstream' },
            s => sub { format_size( $_[0]->filesize || 0 ) },
            n => sub { state $i = 1; $i++ },
        },
    );
    $self->set_lines( map { $fmt->printf($_) } @{ $self->attachments } );
}

sub format_size ($size) {
    my $exp = 0;
    state $units = [ '', qw(K M G T P) ];

    for (@$units) {
        last if $size < 1024;
        $size /= 1024;
        $exp++;
    }

    return sprintf( "%.0f%s", $size, $units->[$exp] );
}

1;
